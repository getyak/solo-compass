/**
 * Trips dataset — frontend-only.
 *
 * Hardcoded sample trips for Solo Compass web Scenario C (`/trip/[slug]`).
 * One sample seeded: `sofia-lisbon-may-2025`.
 *
 * monthLabel / monthLabelZh are display strings, not ISO dates — they are
 * read-only marketing copy, never parsed at runtime.
 */

export interface TripDay {
  readonly title: string;
  readonly titleZh: string;
  readonly places: readonly string[];
  readonly walkedKm: number;
  readonly icon: string;
}

export interface Trip {
  readonly slug: string;
  readonly author: string;
  readonly citySlug: string;
  readonly cityZh: string;
  readonly cityEn: string;
  readonly monthLabel: string;
  readonly monthLabelZh: string;
  readonly intro: string;
  readonly introZh: string;
  readonly quote: string;
  readonly quoteZh: string;
  readonly titleEn: string;
  readonly titleZh: string;
  readonly stats: {
    readonly walkedKm: number;
    readonly places: number;
    readonly favorite: string;
  };
  readonly days: readonly TripDay[];
}

export const TRIPS: Readonly<Record<string, Trip>> = {
  "sofia-lisbon-may-2025": {
    slug: "sofia-lisbon-may-2025",
    author: "SOFIA L",
    citySlug: "lisbon",
    cityZh: "里斯本",
    cityEn: "Lisbon",
    monthLabel: "MAY 2025",
    monthLabelZh: "2025 年 5 月",
    titleEn: "Four days, in Lisbon",
    titleZh: "四天 · 在里斯本",
    intro: "I didn't plan. I opened compass.io/lisbon and followed it for four days.",
    introZh: "我没做攻略。打开了 compass.io/lisbon，跟着它走了四天。",
    quote:
      "I got lost in Alfama three times. Each time, the AI told me not to worry — this alley leads to another miradouro, quieter than the one on the map.",
    quoteZh:
      "我在阿尔法玛迷路了三次。每一次，AI 都告诉我别担心——这条小路通向另一个观景台，比地图上的更安静。",
    stats: {
      walkedKm: 21.4,
      places: 11,
      favorite: "Tasca do Chico",
    },
    days: [
      {
        title: "Arrival · Getting lost · First glass",
        titleZh: "到达 · 走丢 · 第一杯酒",
        places: ["Tasca do Chico", "Miradouro de Santa Catarina", "Pensão Amor"],
        walkedKm: 6.2,
        icon: "◐",
      },
      {
        title: "Fado · Cataplana · By the river",
        titleZh: "法多 · 海鲜饭 · 河边",
        places: ["Time Out Market", "Praça do Comércio", "Cervejaria Ramiro"],
        walkedKm: 8.4,
        icon: "◑",
      },
      {
        title: "Lapa · Old books · A quiet afternoon",
        titleZh: "雷比拉 · 旧书 · 安静的下午",
        places: ["Livraria Bertrand", "A Vida Portuguesa", "Park Bar"],
        walkedKm: 5.1,
        icon: "◒",
      },
      {
        title: "Last morning · Breakfast alone",
        titleZh: "最后的早晨 · 一个人的早餐",
        places: ["Café A Brasileira"],
        walkedKm: 2.3,
        icon: "◓",
      },
    ],
  },
};

export function findTripBySlug(slug: string): Trip | undefined {
  return TRIPS[slug];
}
