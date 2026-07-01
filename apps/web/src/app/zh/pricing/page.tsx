import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import {
  Footer,
  MarketingNav,
  Pricing,
} from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";
import { HomeJsonLd } from "../../_seo";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "价格 · Solo Compass",
  description:
    "一次买断 ¥118，年度 ¥198。永不接广告，永不卖数据，永不做订阅膨胀。可以先免费试用，再决定。",
  alternates: {
    canonical: `${SITE_URL}/zh/pricing`,
    languages: {
      en: `${SITE_URL}/pricing`,
      "zh-CN": `${SITE_URL}/zh/pricing`,
      "x-default": `${SITE_URL}/pricing`,
    },
  },
  openGraph: {
    url: `${SITE_URL}/zh/pricing`,
    title: "Solo Compass · 价格",
    description: "¥118 一次买断，¥198 每年。诚实定价，无广告。",
    images: [{ url: "/og/pricing-zh.png", width: 1200, height: 630 }],
  },
};

const FAQ_ZH = [
  {
    q: "为什么一次买断比年度便宜？",
    a: "因为一次买断锁死现有功能，年度包含未来所有新东西。Craft 和 Fastmail 都是这样。两种都不错，看你更在意哪个：一次付清还是持续升级。",
  },
  {
    q: "Free 和 Pro 有什么区别？",
    a: "Free 给你地图、城市指南、每天 3 次 AI 交叉编译。Pro 去掉每日次数上限，解锁跨城市路线、创建 Rituals、iCloud 同步、打印导出。",
  },
  {
    q: "有学生优惠吗？",
    a: "有 —— 年度半价 ¥99，需要 .edu 邮箱或 UNiDAYS 验证。Phase 1.5 上线。",
  },
  {
    q: "以后会不会接广告？",
    a: "永远不会。如果哪天变了，我们会全额退款所有一次买断的用户。",
  },
  {
    q: "会卖我的数据吗？",
    a: "不会。你的位置永远不离开手机。参见我们的隐私页，四张表列清楚了收集什么、不收集什么。",
  },
  {
    q: "可以先试用吗？",
    a: "可以。Free 版本本身就有用，不是 demo。从 App Store 下载，用一周，再决定。",
  },
];

export default function PricingPageZh() {
  const props = {
    copy: copy.zh,
    locale: "zh" as const,
    homePath: "/zh",
    altPath: "/",
  };
  return (
    <div lang="zh-CN">
      <HomeJsonLd locale="zh" />
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              {copy.zh.pricing.eyebrow}
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">{copy.zh.pricing.title}</h1>
            <p className="ds-body-xl mt-6">{copy.zh.pricing.sub}</p>
          </Container>
        </Section>
        <Pricing {...props} />

        <Section className="border-t border-border-subtle/50">
          <Container width="narrow">
            <Eyebrow dot="sun">常见问题</Eyebrow>
            <h2 className="ds-display-md mt-6 font-display">
              真实用户会问的问题，诚实回答。
            </h2>
            <dl className="mt-12 divide-y divide-border-subtle">
              {FAQ_ZH.map((item, i) => (
                <div key={i} className="py-8">
                  <dt className="font-display text-[20px] font-medium leading-tight text-fg-primary">
                    {item.q}
                  </dt>
                  <dd className="ds-body-lg mt-3 text-fg-muted">{item.a}</dd>
                </div>
              ))}
            </dl>
          </Container>
        </Section>
      </main>
      <Footer {...props} />
    </div>
  );
}
