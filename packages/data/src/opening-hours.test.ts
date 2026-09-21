import { describe, expect, it } from "vitest";
import { parseSimpleOpeningHours, windowsForDay } from "./opening-hours";

describe("parseSimpleOpeningHours", () => {
  it("parses common weekday and weekend schedules", () => {
    const result = parseSimpleOpeningHours("Mo-Fr 08:00-18:00; Sa 09:00-12:00,13:00-17:00; Su off");
    expect(result?.days.Mo).toEqual([{ startMinute: 480, endMinute: 1080 }]);
    expect(result?.days.Sa).toEqual([
      { startMinute: 540, endMinute: 720 },
      { startMinute: 780, endMinute: 1020 },
    ]);
    expect(result?.days.Su).toEqual([]);
  });

  it("parses 24/7", () => {
    const result = parseSimpleOpeningHours("24/7");
    expect(result && windowsForDay(result, 0)).toEqual([{ startMinute: 0, endMinute: 1440 }]);
    expect(result && windowsForDay(result, 6)).toEqual([{ startMinute: 0, endMinute: 1440 }]);
  });

  it("splits overnight windows across local days", () => {
    const result = parseSimpleOpeningHours("Fr 20:00-02:00; Sa 20:00-24:00");
    expect(result?.days.Fr).toEqual([{ startMinute: 1200, endMinute: 1440 }]);
    expect(result?.days.Sa).toEqual([
      { startMinute: 0, endMinute: 120 },
      { startMinute: 1200, endMinute: 1440 },
    ]);
  });

  it("refuses unsupported calendar expressions rather than guessing", () => {
    expect(parseSimpleOpeningHours("Mo-Fr sunrise-sunset")).toBeUndefined();
    expect(parseSimpleOpeningHours("Mo-Fr 08:00-18:00; PH off")).toBeUndefined();
  });
});
