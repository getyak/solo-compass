/**
 * Marketing copy — English + Simplified Chinese.
 * Doc: WEB_LANDING_DESIGN.md §6
 *
 * Nothing here is machine-translated. The Chinese version keeps
 * the same voice (editorial, non-marketing, honest) but not the
 * same sentence structure — parallel translation would sound
 * stiff. See WEB_LANDING_DESIGN.md §6.3 for CN discipline.
 */

export type Locale = "en" | "zh";

export interface Copy {
  nav: {
    features: string;
    pricing: string;
    cities: string;
    blog: string;
    manifesto: string;
    signIn: string;
    getApp: string;
  };
  hero: {
    eyebrow: string;
    h1Lines: string[];
    sub: string;
    ctaPrimary: string;
    ctaSecondary: string;
  };
  problem: {
    eyebrow: string;
    paragraphs: { text: string; muted?: string[] }[];
  };
  pillars: {
    eyebrow: string;
    title: string;
    sub: string;
    items: { dot: "sun" | "omen" | "accent"; title: string; body: string }[];
  };
  trust: {
    eyebrow: string;
    title: string;
    items: { heading: string; body: string }[];
  };
  capabilities: {
    eyebrow: string;
    title: string;
    sub: string;
    intro: string;
  };
  askSolo: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    demoUser: string;
    demoAgent: string;
    demoReason: string;
  };
  blindbox: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    cardHint: string;
    cardReveal: string;
    cardReason: string;
  };
  capsule: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    sealTitle: string;
    sealMeta: string;
    sealBody: string;
  };
  omen: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    cardDate: string;
    cardTitle: string;
    cardLine: string;
  };
  bestNow: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    peakLabel: string;
    peakWindow: string;
    peakReason: string;
  };
  brag: {
    eyebrow: string;
    title: string;
    body: string;
    bullets: string[];
    cardName: string;
    cardMeta: string;
    cardLine: string;
    cardStat1: string;
    cardStat2: string;
    cardStat3: string;
  };
  pricing: {
    eyebrow: string;
    title: string;
    sub: string;
    lifetime: {
      name: string;
      price: string;
      pricePer: string;
      tagline: string;
      cta: string;
      features: string[];
    };
    yearly: {
      badge: string;
      name: string;
      price: string;
      pricePer: string;
      tagline: string;
      cta: string;
      features: string[];
    };
    free: string;
  };
  footer: {
    tagline: string;
    columns: { heading: string; links: { label: string; href: string }[] }[];
    bottom: string;
  };
  langSwitch: string;
}

export const copy: Record<Locale, Copy> = {
  en: {
    nav: {
      features: "Features",
      pricing: "Pricing",
      cities: "Cities",
      blog: "Journal",
      manifesto: "Manifesto",
      signIn: "Sign in",
      getApp: "Get on App Store",
    },
    hero: {
      eyebrow: "since 2026 · made for iOS 17+",
      h1Lines: ["A map where", "every dot is worth", "a solo detour."],
      sub: "Solo Compass is a map-first companion for people traveling alone. No feed. No ads. Just experiences worth your afternoon.",
      ctaPrimary: "Get on App Store",
      ctaSecondary: "See how it works",
    },
    problem: {
      eyebrow: "Why we built this",
      paragraphs: [
        { text: "It's 4 PM." },
        { text: "You're alone in a city you don't know." },
        {
          text: "You could open Google Maps — but the top-rated café will be full of couples on dates.",
          muted: ["Google Maps"],
        },
        {
          text: "You could open 小红书 — but the \"instagrammable\" spot is a queue of tripods.",
          muted: ["小红书"],
        },
        {
          text: "You could ask ChatGPT — but it will confidently invent a place that closed last year.",
          muted: ["ChatGPT"],
        },
        {
          text: "We built Solo Compass because none of those felt like what an old friend who knew the city would tell you.",
        },
      ],
    },
    pillars: {
      eyebrow: "Three non-negotiables",
      title: "How Solo Compass is different.",
      sub: "Three design pillars from day one. If a feature pulls away from any of them, it doesn't ship.",
      items: [
        {
          dot: "sun",
          title: "Map-first",
          body: "The map is the home screen. No tabs. No drawer. No onboarding. Everything happens on the map.",
        },
        {
          dot: "omen",
          title: "Experience-as-unit",
          body: "Not places — verb-bound, time-anchored things to do. \"Watch sunset paint the stupas at 5:30\" beats \"Wat Suan Dok.\"",
        },
        {
          dot: "accent",
          title: "AI doesn't decide",
          body: "AI narrows a thousand options to five, cites its sources, and shows its uncertainty. You make the call.",
        },
      ],
    },
    trust: {
      eyebrow: "How we treat you",
      title: "Three promises we don't break.",
      items: [
        {
          heading: "Privacy is a promise, not a checkbox.",
          body: "Your location never leaves your phone. No accounts to try. No email. No \"sign up with Google.\" Anonymous by default.",
        },
        {
          heading: "AI is a filter, not an oracle.",
          body: "Every AI suggestion shows its sources and how confident it is. Freshness signals: verified this month, fading, questioned. You know what you're trusting.",
        },
        {
          heading: "Pricing is honest.",
          body: "$29 one-time, or $50 a year. That's it. No ads ever. No selling your data ever. No free-then-paywall bait.",
        },
      ],
    },
    capabilities: {
      eyebrow: "What you actually get",
      title: "Six things nobody else does the way we do.",
      sub: "Not a feature list. Six rituals built for a person traveling alone — each takes 30 seconds to try and rewires how you use a map.",
      intro: "Every tile below is a real screen from the app.",
    },
    askSolo: {
      eyebrow: "01 · Ask Solo",
      title: "The friend in every city, in your pocket.",
      body: "Long-press anywhere on the map, or hold to talk. Solo reads the neighborhood, the time of day, the weather — and answers in cards, not walls of text. Every recommendation cites its sources.",
      bullets: [
        "Voice-first — hold to talk, release to send",
        "Grounded on the map you're looking at, not the world",
        "Shows its reasoning trace — never a black box",
      ],
      demoUser: "Somewhere quiet I can read for 2 hours. Not a chain.",
      demoAgent: "Three candidates within 8 min walk.",
      demoReason: "Ranked by ambient dB (measured), power outlets, and how full a solo traveler said it was Tuesday afternoon.",
    },
    blindbox: {
      eyebrow: "02 · Blindbox",
      title: "For the days you can't choose.",
      body: "Some afternoons the tyranny of choice is the enemy. Tap the blindbox and Solo picks one experience for you, based on where you are and what fits this hour. You can't preview it. That's the point.",
      bullets: [
        "One decision, taken out of your hands",
        "Only opens experiences that match this hour of this day",
        "Cannot re-roll — the whole point is to commit",
      ],
      cardHint: "Chiang Mai · 4:12 PM · sunny",
      cardReveal: "A rooftop nobody's told you about.",
      cardReason: "Golden hour hits the mountains at 5:47. You're 12 min away. Café closes at 8.",
    },
    capsule: {
      eyebrow: "03 · Time Capsule",
      title: "Leave a note for a future you.",
      body: "Standing somewhere you love — a bench, a corner, a viewpoint? Seal a capsule to that exact spot. Return in six months and it opens. Or leave it for whoever you were.",
      bullets: [
        "Anchored to a geofence — opens only when you're back",
        "Text, voice, or photo — sealed on device",
        "Time-locks: 1 month · 6 months · 1 year · when-you're-ready",
      ],
      sealTitle: "Sealed at Nimman corner café",
      sealMeta: "opens in 6 months · when you're here",
      sealBody: "\"You were tired today. You almost skipped this walk. Remember it was worth it.\"",
    },
    omen: {
      eyebrow: "04 · Daily Omen",
      title: "One small prompt, every morning.",
      body: "Not a horoscope. One quiet card at breakfast — a nudge Solo drew from your city, your rhythm, the weather. A gentle direction for the day, not a schedule.",
      bullets: [
        "Draws once per morning — no scroll, no feed",
        "Reads local weather, calendar, and your last week",
        "Written by a language model, tuned to be terse",
      ],
      cardDate: "Tuesday · Chiang Mai",
      cardTitle: "Today, take the long way.",
      cardLine: "The mango tree at Wat Suan Dok drops fruit around 3 PM. Nobody's told the algorithm.",
    },
    bestNow: {
      eyebrow: "05 · Best Now",
      title: "Every place has a golden hour. We show it.",
      body: "Solo Compass knows when each experience is best — not \"open,\" but at its peak. A café's quiet window is 8–10 AM. A viewpoint's is 5:47 PM sharp. Every card shows a live heatmap of when to go.",
      bullets: [
        "Learned from solo travelers' honest reports, not vendor claims",
        "Live now-badge when you're inside the peak window",
        "Countdown when peak is soon — silent when it's not",
      ],
      peakLabel: "Peak in 42 min",
      peakWindow: "5:47 – 6:15 PM · golden hour",
      peakReason: "Light hits the stupas at this angle exactly 28 minutes a day.",
    },
    brag: {
      eyebrow: "06 · Brag Card",
      title: "A travel passport, not a highlight reel.",
      body: "At the end of a trip Solo compiles what you actually did — the walks, the peaks you hit, the places nobody else on the app has been. One shareable card. Zero engagement optimization.",
      bullets: [
        "Auto-composed from your archive — you don't caption anything",
        "Shows genuine rarity, not likes",
        "Exports to print — magazine-style, ready for a frame",
      ],
      cardName: "Nikita · Solo Traveler",
      cardMeta: "Chiang Mai · 8 days · Feb 2026",
      cardLine: "Walked 47.2 km. Wrote 3 capsules. Found 1 place nobody had marked.",
      cardStat1: "Experiences",
      cardStat2: "Kilometers",
      cardStat3: "Rare finds",
    },
    pricing: {
      eyebrow: "Pricing",
      title: "One decision. Two options.",
      sub: "Pay once and it's yours. Or pay yearly and get first access to everything new. Either way, no ads, no data selling, no subscription bloat.",
      lifetime: {
        name: "Lifetime",
        price: "$29",
        pricePer: "one time",
        tagline: "Every feature today. Forever yours.",
        cta: "Buy Once",
        features: [
          "Unlimited AI cross-referencing",
          "Custom routes across cities",
          "Rituals · Time Capsule · Omen · Blindbox",
          "Print export (magazine-style journal)",
          "iCloud sync across devices",
          "Every future minor update",
        ],
      },
      yearly: {
        badge: "Most popular",
        name: "Yearly",
        price: "$50",
        pricePer: "per year",
        tagline: "Everything in Lifetime, plus first access to what's next.",
        cta: "Start Yearly",
        features: [
          "Everything in Lifetime",
          "First access to new AI models",
          "First access to new Rituals",
          "Priority support",
          "Contribute to the roadmap",
          "Cancel anytime — no lock-in",
        ],
      },
      free: "Or try Free first — no card, no signup",
    },
    footer: {
      tagline:
        "Solo Compass is made by one person, in Kyoto. No VC. No ads. No tracking. Answerable to you.",
      columns: [
        {
          heading: "Product",
          links: [
            { label: "Features", href: "/#features" },
            { label: "Pricing", href: "/pricing" },
            { label: "Download", href: "/download" },
          ],
        },
        {
          heading: "Company",
          links: [
            { label: "Manifesto", href: "/manifesto" },
            { label: "Contact", href: "mailto:hello@solocompass.app" },
          ],
        },
        {
          heading: "Legal",
          links: [
            { label: "Privacy", href: "/privacy" },
          ],
        },
      ],
      bottom: "© 2026 Solo Compass · Made with respect for solo travelers.",
    },
    langSwitch: "中文",
  },
  zh: {
    nav: {
      features: "功能",
      pricing: "价格",
      cities: "城市",
      blog: "刊物",
      manifesto: "宣言",
      signIn: "登录",
      getApp: "App Store 下载",
    },
    hero: {
      eyebrow: "since 2026 · 面向 iOS 17+",
      h1Lines: ["每一个点", "都值得你", "独自绕路一趟。"],
      sub: "Solo Compass 是为独自旅行者做的地图。没有信息流，没有广告，只有值得你度过一个下午的体验。",
      ctaPrimary: "App Store 下载",
      ctaSecondary: "看看它是什么样",
    },
    problem: {
      eyebrow: "为什么我们做这个",
      paragraphs: [
        { text: "下午 4 点。" },
        { text: "你独自在一座陌生的城市。" },
        {
          text: "你可以打开 Google 地图 —— 但热门咖啡馆里全是情侣约会。",
          muted: ["Google 地图"],
        },
        {
          text: "你可以刷小红书 —— 但\"出片圣地\"排着三脚架的长队。",
          muted: ["小红书"],
        },
        {
          text: "你可以问 ChatGPT —— 但它会自信地给你一个去年就关门的店。",
          muted: ["ChatGPT"],
        },
        {
          text: "我们做 Solo Compass，是因为以上都不像一个熟悉这座城的本地朋友会告诉你的话。",
        },
      ],
    },
    pillars: {
      eyebrow: "三条不可动摇的原则",
      title: "Solo Compass 和别人不一样，在哪。",
      sub: "从第一天起就定下三条设计准则。任何功能只要偏离其一，就不会被做进产品。",
      items: [
        {
          dot: "sun",
          title: "地图为家",
          body: "地图就是首页。没有 tab，没有抽屉，没有引导页。一切都在地图上发生。",
        },
        {
          dot: "omen",
          title: "以\"体验\"为单位",
          body: "不是地点，是带动词、带时间、带感官的具体事。「下午 5:30 看夕阳把白塔染成蜜色」比「双龙寺」更有信息。",
        },
        {
          dot: "accent",
          title: "AI 不替你决定",
          body: "AI 把一千个选项收敛到五个，标注来源，展示不确定性。选哪个，由你。",
        },
      ],
    },
    trust: {
      eyebrow: "我们怎么对你",
      title: "三个不会破的承诺。",
      items: [
        {
          heading: "隐私是承诺，不是勾选项。",
          body: "你的位置永远不离开你的手机。试用无需注册、无需邮箱、无需\"Google 登录\"。默认匿名。",
        },
        {
          heading: "AI 是过滤器，不是神谕。",
          body: "每条 AI 建议都标注来源和置信度。新鲜度信号：本月已核实、正在褪色、被质疑。你知道自己在信什么。",
        },
        {
          heading: "定价是诚实的。",
          body: "一次性 ¥118，或每年 ¥198。就这两档。永远不接广告，永远不卖数据，永远不做\"免费然后付费墙\"的诱饵。",
        },
      ],
    },
    capabilities: {
      eyebrow: "你实际能拿到什么",
      title: "六件事，别人不这么做。",
      sub: "不是功能清单，是六个为独自旅行者做的仪式。每个 30 秒内可上手，能重新改写你使用地图的方式。",
      intro: "下面每张卡都是 App 里的真实界面。",
    },
    askSolo: {
      eyebrow: "01 · 問 Solo",
      title: "每座城市都有的那个懂行朋友。",
      body: "长按地图任意处，或按住语音键。Solo 会读取当前街区、时间、天气 —— 用卡片回答你，而不是一大段文字。每条建议都标注来源。",
      bullets: [
        "语音优先 —— 按住说话，松开发送",
        "锚定在你正看的地图上，不是漫无边际",
        "推理过程可展开 —— 不做黑盒",
      ],
      demoUser: "找个安静地方读书 2 小时，别是连锁店。",
      demoAgent: "8 分钟步行内 3 个候选。",
      demoReason: "按环境音分贝（实测）、有无插座、以及独行者上个周二下午的忙碌记录排序。",
    },
    blindbox: {
      eyebrow: "02 · 盲盒",
      title: "选择困难的时候，交给它。",
      body: "有些下午，选择本身是敌人。点开盲盒，Solo 根据你所在的位置和此刻的时间，替你挑一件事。事前不能预览。这就是重点。",
      bullets: [
        "把\"选什么\"从你手上拿走",
        "只推此时此地此刻合适的体验",
        "不允许重开 —— 就是要你去做",
      ],
      cardHint: "清迈 · 下午 4:12 · 晴",
      cardReveal: "一个没人告诉过你的天台。",
      cardReason: "5:47 山头开始泛金。你走 12 分钟能到。咖啡馆 8 点打烊。",
    },
    capsule: {
      eyebrow: "03 · 时光胶囊",
      title: "给未来的自己写一张便条。",
      body: "站在你喜欢的地方 —— 一条长椅、一个转角、一处观景台 —— 把胶囊封在这个坐标上。半年后回来，它自动打开。或者留给下一个到这里的你。",
      bullets: [
        "绑在地理围栏上 —— 你回来才能开",
        "文字、语音、照片 —— 都在本地封存",
        "时锁：1 个月 · 6 个月 · 1 年 · 等你准备好",
      ],
      sealTitle: "封存于宁曼路转角咖啡馆",
      sealMeta: "6 个月后 · 你回来时开启",
      sealBody: "「你今天很累。差点就没走完这条路。记住这一趟值得。」",
    },
    omen: {
      eyebrow: "04 · 每日签",
      title: "每天早上，一句轻推。",
      body: "不是星座运势。早餐时一张安静的卡片 —— Solo 结合你的城市、你的节奏和天气写的一句提醒。给今天一个方向，不是一份日程。",
      bullets: [
        "每天早上抽一张 —— 无信息流，无红点",
        "读取当地天气、日程和你过去一周",
        "由语言模型撰写，被调教得很克制",
      ],
      cardDate: "周二 · 清迈",
      cardTitle: "今天，绕远路。",
      cardLine: "双龙寺那棵芒果树下午 3 点会落果。没人告诉过算法。",
    },
    bestNow: {
      eyebrow: "05 · 此刻最佳",
      title: "每个地方都有黄金时刻。我们标出来。",
      body: "Solo Compass 知道每个体验在哪个时段最好 —— 不是「营业中」，是「正在最佳」。咖啡馆的安静窗口是早 8-10 点，观景台是傍晚 5:47。每张卡片都有一张实时的最佳时段热力图。",
      bullets: [
        "从独行者的诚实反馈里学，不是店主自吹",
        "在黄金窗口内会亮出一个 Now 徽章",
        "临近黄金时刻才倒计时 —— 平时静默",
      ],
      peakLabel: "42 分钟后最佳",
      peakWindow: "17:47 – 18:15 · 金光时段",
      peakReason: "光线以这个角度照到白塔，一天正好 28 分钟。",
    },
    brag: {
      eyebrow: "06 · 旅记名片",
      title: "旅行护照，不是精彩集锦。",
      body: "一次旅行结束，Solo 会把你真实走过的路线、你踩到的最佳时刻、别人都没去过的地方汇成一张可分享的卡片。不做话题，不做点赞。",
      bullets: [
        "自动从你的档案里编 —— 不用你写任何标题",
        "呈现真实的稀有度，不是点赞数",
        "可导出打印 —— 杂志排版，可以装裱",
      ],
      cardName: "Nikita · 独行者",
      cardMeta: "清迈 · 8 天 · 2026 年 2 月",
      cardLine: "走了 47.2 公里。封了 3 个胶囊。找到 1 个没被标记过的地方。",
      cardStat1: "体验数",
      cardStat2: "公里",
      cardStat3: "稀有发现",
    },
    pricing: {
      eyebrow: "价格",
      title: "一次决定。两种选择。",
      sub: "一次付清，永远是你的。或按年订阅，第一时间用到所有新功能。无论哪种，都没有广告，没有数据变现，没有订阅膨胀。",
      lifetime: {
        name: "一次买断",
        price: "¥118",
        pricePer: "一次付清",
        tagline: "现有全部功能，永远归你。",
        cta: "一次买断",
        features: [
          "无限次 AI 交叉编译",
          "跨城市自定义路线",
          "Rituals · 时光胶囊 · 每日预兆 · 盲盒",
          "杂志式旅记导出打印",
          "iCloud 跨设备同步",
          "所有未来次要更新",
        ],
      },
      yearly: {
        badge: "多数人的选择",
        name: "年度",
        price: "¥198",
        pricePer: "每年",
        tagline: "包含一次买断全部功能 · 首发新功能",
        cta: "订阅年度",
        features: [
          "包含一次买断所有内容",
          "第一时间用上新 AI 模型",
          "第一时间用上新 Rituals",
          "优先支持",
          "参与路线图讨论",
          "随时取消，无锁定",
        ],
      },
      free: "或先免费试用 —— 无需信用卡，无需注册",
    },
    footer: {
      tagline:
        "Solo Compass 由一个人在京都独立开发。没有 VC，没有广告，没有追踪。只对你负责。",
      columns: [
        {
          heading: "产品",
          links: [
            { label: "功能", href: "/zh/#features" },
            { label: "价格", href: "/zh/pricing" },
            { label: "下载", href: "/download" },
          ],
        },
        {
          heading: "关于",
          links: [
            { label: "宣言", href: "/zh/manifesto" },
            { label: "联系", href: "mailto:hello@solocompass.app" },
          ],
        },
        {
          heading: "法律",
          links: [
            { label: "隐私", href: "/zh/privacy" },
          ],
        },
      ],
      bottom: "© 2026 Solo Compass · 尊重每一位独自出发的人。",
    },
    langSwitch: "English",
  },
};
