/**
 * Lisbon dataset — frontend-only.
 *
 * Prototype dataset for Solo Compass web Scenario A (`/lisbon`) and
 * Scenario D (`/experience/[id]`). Intentionally NOT mapped to
 * `@solo-compass/core`'s `Experience` type — the design uses richer fields
 * (zh/en bilingual, AI reason, magazine "moment" prose, sources count) that
 * the canonical schema doesn't yet model.
 *
 * Coordinates `x` / `y` are SVG canvas units (viewBox 0–1000 × 0–700),
 * NOT geographic. They match `WebLisbonMap`'s drawn streets and labels.
 * Real `[lng, lat]` should be added separately when wiring to Supabase.
 *
 * `bestHours` are local-to-Lisbon ints (CLAUDE.md convention).
 * `lastVerified` is ISO 8601 date-only.
 */

export const WEB_CATS = {
  miradouro: { en: "Viewpoints", zh: "观景台", color: "#C98628", short: "view" },
  cafe: { en: "Cafés", zh: "咖啡", color: "#A66A00", short: "cafe" },
  food: { en: "Food", zh: "吃饭", color: "#A23A2E", short: "food" },
  fado: { en: "Fado", zh: "法多", color: "#3F4B7A", short: "fado" },
  walk: { en: "Walks", zh: "散步", color: "#4C7A3F", short: "walk" },
  hidden: { en: "Hidden", zh: "冷门", color: "#6B5B3F", short: "hidden" },
  bookshop: { en: "Bookshops", zh: "书店", color: "#5D3000", short: "book" },
} as const;

export type WebCategoryId = keyof typeof WEB_CATS;

export const WEB_CITY = {
  slug: "lisbon",
  zh: "里斯本",
  en: "Lisbon",
  country: "Portugal",
  countryZh: "葡萄牙",
  tagline: "Seven hills, four trams, one river that catches the evening.",
  taglineZh: "七座山，四条电车，一条接住傍晚的河。",
  experienceCount: 47,
  cityDeck: ["Lisbon · Portugal", "Porto · Portugal", "Lyon · France", "Tbilisi · Georgia"],
} as const;

export interface WebExperience {
  readonly id: string;
  readonly title: string;
  readonly titleZh: string;
  readonly place: string;
  readonly placeZh: string;
  readonly cat: WebCategoryId;
  readonly x: number;
  readonly y: number;
  readonly walkMin: number;
  readonly neighborhood: string;
  readonly bestHours: readonly number[];
  readonly durationMin: number;
  readonly why: string;
  readonly whyZh: string;
  readonly moment: string;
  readonly momentZh: string;
  readonly crowd: "quiet" | "calm" | "busy";
  readonly soloScore: number;
  readonly sources: number;
  readonly lastVerified: string;
  readonly aiReason: string;
  readonly aiReasonZh: string;
  readonly tags: readonly string[];
  readonly tagsZh: readonly string[];
  readonly pricePill: string;
}

export const WEB_EXPS: readonly WebExperience[] = [
  {
    id: "miradouro-graca",
    title: "Watch the city tilt at sunset",
    titleZh: "在倾斜的城市里等日落",
    place: "Miradouro da Graça",
    placeZh: "格拉萨观景台",
    cat: "miradouro",
    x: 612,
    y: 286,
    walkMin: 14,
    neighborhood: "Graça",
    bestHours: [18, 19, 20],
    durationMin: 45,
    why: "Seven hills face you, the castle on your left, the river on your right. The light goes pink for nine minutes.",
    whyZh: "七座山在你面前，城堡在左，大河在右。光会粉九分钟。",
    moment: "A grandfather plays trumpet, badly, and nobody minds.",
    momentZh: "一位老先生吹小号，吹得不准，没人介意。",
    crowd: "busy",
    soloScore: 8,
    sources: 14,
    lastVerified: "2026-04-22",
    aiReason:
      "You saved two viewpoints in Porto. Graça has a wider sky than the others — the river bends, the castle frames it.",
    aiReasonZh: "你在波尔图收藏过两个观景台。Graça 的天空更开阔——河在这里转弯，城堡正好框住它。",
    tags: ["solo-friendly", "sunset", "no booking"],
    tagsZh: ["一个人也行", "日落", "不用预订"],
    pricePill: "€0",
  },
  {
    id: "pasteis-de-belem",
    title: "Eat a pastel where they invented it",
    titleZh: "在发明它的地方吃一只蛋挞",
    place: "Pastéis de Belém",
    placeZh: "贝伦蛋挞老店",
    cat: "food",
    x: 220,
    y: 510,
    walkMin: 32,
    neighborhood: "Belém",
    bestHours: [10, 11, 16, 17],
    durationMin: 25,
    why: "The recipe lives in a sealed room. Three people know it. The line moves fast — you'll be inside in eight minutes.",
    whyZh: "配方锁在一间封闭的房间里。只有三个人知道。队伍走得快——八分钟就进得去。",
    moment: "Cinnamon goes on at the table, not in the kitchen.",
    momentZh: "肉桂是在桌上撒的，不是厨房里。",
    crowd: "busy",
    soloScore: 7,
    sources: 22,
    lastVerified: "2026-04-30",
    aiReason:
      "You like origin stories. This is one of three places in Lisbon where the food predates the country it's in.",
    aiReasonZh: "你喜欢起源的故事。里斯本只有三个地方的食物比这个国家本身还老，这是其中之一。",
    tags: ["cash ok", "queue moves", "eat in"],
    tagsZh: ["可现金", "队伍快", "坐下吃"],
    pricePill: "€1.40",
  },
  {
    id: "a-vida-portuguesa",
    title: "Touch every object in a hundred-year shop",
    titleZh: "在百年老店里把每一样东西摸一遍",
    place: "A Vida Portuguesa",
    placeZh: "A Vida Portuguesa",
    cat: "hidden",
    x: 400,
    y: 380,
    walkMin: 12,
    neighborhood: "Chiado",
    bestHours: [11, 12, 13, 14, 15, 16],
    durationMin: 50,
    why: "Soaps, sardines, notebooks, blankets — every product has a label written by someone who cared. The floors creak.",
    whyZh: "肥皂、沙丁鱼、笔记本、毯子——每件商品的标签都是认真写的人写的。地板会吱呀响。",
    moment: "The shopkeeper will let you smell three soaps before suggesting one.",
    momentZh: "店主会让你闻完三块肥皂，再温柔地推荐一块。",
    crowd: "calm",
    soloScore: 9,
    sources: 9,
    lastVerified: "2026-04-12",
    aiReason:
      "Reading time: you lingered on shops in Porto. This one is the most articulate of its kind in Iberia.",
    aiReasonZh: "阅读时长：你在波尔图的店铺页面停留得久。这家是伊比利亚同类里最有想法的。",
    tags: ["rainy day", "gifts", "no rush"],
    tagsZh: ["下雨天去", "送礼", "不赶"],
    pricePill: "€€",
  },
  {
    id: "tasca-do-chico",
    title: "Stand in a tasca and let fado find you",
    titleZh: "站在一家小酒馆里让法多找到你",
    place: "Tasca do Chico",
    placeZh: "Tasca do Chico",
    cat: "fado",
    x: 478,
    y: 422,
    walkMin: 18,
    neighborhood: "Bairro Alto",
    bestHours: [21, 22, 23],
    durationMin: 90,
    why: "No stage, no microphone. The singer stands among the tables. When she begins, the lights drop and people stop chewing.",
    whyZh: "没有舞台，也没有话筒。歌者站在桌子之间。她一开口，灯就暗下去，所有人停止嚼东西。",
    moment: "Three songs, then they pass a basket. Five euros is right.",
    momentZh: "三首歌后会传一个篮子。五欧元正好。",
    crowd: "busy",
    soloScore: 8,
    sources: 18,
    lastVerified: "2026-04-18",
    aiReason:
      "You mentioned you don't like reserved tables. Chico doesn't take bookings — you stand at the bar, which is the best seat anyway.",
    aiReasonZh: "你说过不喜欢预订座位。Chico 不接受预订——你站在吧台，那本来就是最好的位置。",
    tags: ["no booking", "late", "standing room"],
    tagsZh: ["不接受预订", "夜里", "站着也行"],
    pricePill: "€10–20",
  },
  {
    id: "feira-da-ladra",
    title: "Walk the thieves' market on a Tuesday morning",
    titleZh: "周二一早去逛贼市",
    place: "Feira da Ladra",
    placeZh: "小偷市场",
    cat: "walk",
    x: 666,
    y: 322,
    walkMin: 22,
    neighborhood: "Alfama",
    bestHours: [8, 9, 10, 11],
    durationMin: 75,
    why: "900 years of stuff. A 1972 typewriter, a child's first communion photo, a single Cuban shoe. Don't buy on the first lap.",
    whyZh:
      "九百年的东西。1972 年的打字机，一张小孩首领圣体的照片，一只孤零零的古巴鞋。第一圈别买。",
    moment: "The vendor will quote double; you offer half; you meet in the middle.",
    momentZh: "卖家先报双倍，你回半价，最后在中间见面。",
    crowd: "calm",
    soloScore: 9,
    sources: 11,
    lastVerified: "2026-04-08",
    aiReason:
      "You spent eighteen minutes on the Alfama walk page. The market lives in the same web of streets — go on the way down.",
    aiReasonZh: "你在 Alfama 散步页面停留了十八分钟。这个市场就在同一片街区里——下山顺路过去。",
    tags: ["Tue · Sat", "morning", "cash"],
    tagsZh: ["周二·周六", "清晨", "现金"],
    pricePill: "free",
  },
  {
    id: "livraria-bertrand",
    title: "Read upstairs at the world's oldest bookshop",
    titleZh: "在世界上最古老的书店楼上读一会儿",
    place: "Livraria Bertrand",
    placeZh: "贝特朗书店",
    cat: "bookshop",
    x: 442,
    y: 396,
    walkMin: 8,
    neighborhood: "Chiado",
    bestHours: [14, 15, 16, 17],
    durationMin: 60,
    why: "Open since 1732. Pessoa drank coffee in the chair by the window. The English shelves are upstairs, mostly fiction.",
    whyZh: "1732 年至今。佩索阿坐过窗边那把椅子喝咖啡。英文书在楼上，多是小说。",
    moment: "There's a card you can stamp; ten stamps gets you a free book of any size.",
    momentZh: "柜台有一张卡可以盖章；盖满十个，可以免费换一本任意大小的书。",
    crowd: "quiet",
    soloScore: 9,
    sources: 7,
    lastVerified: "2026-04-25",
    aiReason:
      "You read on second floors in Chiang Mai too — this is the Lisbon equivalent. Quieter, older.",
    aiReasonZh: "你在清迈也喜欢二楼读书——这是里斯本版的。更安静，更老。",
    tags: ["quiet", "rainy day", "pessoa"],
    tagsZh: ["安静", "下雨天", "佩索阿"],
    pricePill: "browse free",
  },
  {
    id: "tram-28",
    title: "Ride tram 28 at 7am before the tourists wake up",
    titleZh: "7 点骑 28 路电车，在游客醒之前",
    place: "Tram 28",
    placeZh: "28 路电车",
    cat: "walk",
    x: 540,
    y: 360,
    walkMin: 4,
    neighborhood: "Old town",
    bestHours: [7, 8],
    durationMin: 40,
    why: "The same yellow car that everyone Instagrams at noon — but at 7am it carries pensioners going to mass and you. They will nod.",
    whyZh:
      "中午被人疯狂拍照的同一辆黄色电车——早上 7 点，里面坐的是去望弥撒的退休老人，加你。他们会点头。",
    moment: "It rocks hard around the cathedral curve. Hold the leather strap, not the seat.",
    momentZh: "到大教堂那个弯会摇得厉害。抓皮带，别抓座椅。",
    crowd: "quiet",
    soloScore: 9,
    sources: 13,
    lastVerified: "2026-04-29",
    aiReason:
      "You said you'd rather skip the famous things. The famous things are still good — at the right hour they become not famous.",
    aiReasonZh: "你说想跳过那些「必去」的。其实它们没毛病——在对的时间，它们就不「必去」了。",
    tags: ["early", "crowd-free", "€3"],
    tagsZh: ["早起", "没人", "€3"],
    pricePill: "€3",
  },
];

export function findExperienceById(id: string): WebExperience | undefined {
  return WEB_EXPS.find((e) => e.id === id);
}

export function nearbyExperiences(exp: WebExperience, count = 2): readonly WebExperience[] {
  return WEB_EXPS.filter((e) => e.id !== exp.id)
    .map((e) => ({ e, d: Math.hypot(exp.x - e.x, exp.y - e.y) }))
    .sort((a, b) => a.d - b.d)
    .slice(0, count)
    .map((x) => x.e);
}
