import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "宣言 · Solo Compass",
  description:
    "为什么会有 Solo Compass。一份关于独自旅行、诚实 AI，以及为什么我们选择那条更难的路——不接广告、不做追踪、不融资——即使这意味着走得更慢的短宣言。",
  alternates: {
    canonical: `${SITE_URL}/zh/manifesto`,
    languages: {
      en: `${SITE_URL}/manifesto`,
      "zh-CN": `${SITE_URL}/zh/manifesto`,
      "x-default": `${SITE_URL}/manifesto`,
    },
  },
  openGraph: {
    type: "article",
    url: `${SITE_URL}/zh/manifesto`,
    title: "Solo Compass · 宣言",
    description: "关于独自旅行、诚实 AI、不接广告不追踪不融资的短宣言。",
    locale: "zh_CN",
    alternateLocale: "en_US",
    images: [{ url: "/og/manifesto-zh.png", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · 宣言",
    description: "关于独自旅行、诚实 AI、不接广告不追踪不融资的短宣言。",
    images: ["/og/manifesto-zh.png"],
  },
};

const PARAGRAPHS_ZH: { heading: string; body: string }[] = [
  {
    heading: "地图应该是主角。",
    body: "所有其他旅行 app 都在把你推向信息流、榜单和「为你推荐」。地图只是一个 tab。在 Solo Compass 里，地图就是这个 app。你打开看到的第一件事是「你在哪里」和「你周围有什么」——经过筛选、排序、诚实。不是因为我们信奉极简主义，而是因为一个独自旅行者下午四点在陌生城市里，真的就只需要这个。",
  },
  {
    heading: "以体验为单位，而不是地点。",
    body: "「蓝瓶咖啡」是一个地点。「一个安静的角落，我可以读两小时书而不会被店员催走」是一种体验。地图存的是地点，人记住的是体验。我们把核心数据模型建在 Experience 上，带情绪标签、最佳时间、感官笔记、独处友好度，所以 app 能回答真实的问题，不只是把针插在地图上。",
  },
  {
    heading: "AI 亮明底牌。",
    body: "我们用 AI 来筛选和解释，而不是替代你的判断。每一次排序都展示引用来源——Wikimedia、OSM、官方页面、可验证的评价。每一次推荐都标注置信度。模型不确定时会明说，两个来源冲突时都会展示。独自旅行是高风险场景，不透明的 AI 不能接受。",
  },
  {
    heading: "永不接广告，永不追踪。",
    body: "一个 app 接了广告，激励就和你分道扬镳了：它必须抢占你的注意力、必须为付费合作伙伴虚高评分、必须知道你在哪里买了什么。Solo Compass 只用一种方式赚钱：你付了钱。如果我们哪天违背这个承诺，欠每一位一次买断用户全额退款。这一条写进了我们的条款里。",
  },
  {
    heading: "京都独立开发，对你负责。",
    body: "一个人。没有 VC 逼着不惜代价增长。没有董事会。也就没有暗黑模式、没有 A/B test 压榨转化、没有把你当成指标的增长手段。你写邮件来，是一个真人回你——通常一天内，有时候会附上你问的那条街道的照片。",
  },
  {
    heading: "写给一个人订机票的你。",
    body: "不是网红博主，不是团队旅行者，不是打卡清单派。是那个存了几个月钱、选择一个人出发、希望这趟旅行属于自己——而不是被别人的算法过滤过——的你。如果你就是这样的人，我们是为你做的。",
  },
];

export default function ManifestoZh() {
  const props = {
    copy: copy.zh,
    locale: "zh" as const,
    homePath: "/zh",
    altPath: "/manifesto",
  };
  return (
    <div lang="zh-CN">
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              宣言
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">一款为独自出发的人做的地图 app。</h1>
            <p className="ds-body-xl mt-6 text-fg-muted">
              六件我们相信的事。写在第一行代码之前，到今天依然成立。
            </p>
          </Container>
        </Section>

        <Section className="pt-4 pb-24">
          <Container width="narrow">
            <div className="space-y-16">
              {PARAGRAPHS_ZH.map((p, i) => (
                <article key={i}>
                  <h2 className="font-display text-[28px] font-medium leading-tight text-fg-primary md:text-[32px]">
                    {i + 1}. {p.heading}
                  </h2>
                  <p className="ds-body-lg mt-4 text-fg-muted">{p.body}</p>
                </article>
              ))}
            </div>
          </Container>
        </Section>
      </main>
      <Footer {...props} />
    </div>
  );
}
