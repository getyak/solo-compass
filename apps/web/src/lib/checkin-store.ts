export interface LocalCheckin {
  experienceId: string;
  timestamp: string; // ISO 8601
  coords?: [number, number]; // [lng, lat]
}

const STORAGE_KEY = "sc:checkins";

export function readCheckins(): LocalCheckin[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    return JSON.parse(raw) as LocalCheckin[];
  } catch {
    return [];
  }
}

export function writeCheckin(checkin: LocalCheckin): LocalCheckin[] {
  const existing = readCheckins().filter((c) => c.experienceId !== checkin.experienceId);
  const updated = [...existing, checkin];
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
  } catch {
    // storage full or unavailable — best effort
  }
  return updated;
}

export function hasCheckin(experienceId: string): boolean {
  return readCheckins().some((c) => c.experienceId === experienceId);
}

const IOS_PROMPT_KEY = "sc:ios-prompt-dismissed-at";

export function getIOSPromptDismissedAt(): number | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(IOS_PROMPT_KEY);
  return raw ? Number(raw) : null;
}

export function dismissIOSPrompt(): void {
  try {
    localStorage.setItem(IOS_PROMPT_KEY, String(Date.now()));
  } catch {
    // best effort
  }
}

export function isIOSPromptSnoozed(): boolean {
  const dismissedAt = getIOSPromptDismissedAt();
  if (dismissedAt === null) return false;
  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
  return Date.now() - dismissedAt < sevenDaysMs;
}
