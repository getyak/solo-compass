import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "隐私 · Solo Compass",
  description:
    "Solo Compass 会收集什么、不会收集什么、你的数据存在哪里。位置留在设备上，不接广告 SDK，不做第三方追踪。用大白话写给普通人看，不是律师版本。",
  alternates: {
    canonical: `${SITE_URL}/zh/privacy`,
    languages: {
      en: `${SITE_URL}/privacy`,
      "zh-CN": `${SITE_URL}/zh/privacy`,
      "x-default": `${SITE_URL}/privacy`,
    },
  },
  openGraph: {
    type: "article",
    url: `${SITE_URL}/zh/privacy`,
    title: "Solo Compass · 隐私",
    description: "位置留在设备上，不接广告 SDK，不做第三方追踪。",
    locale: "zh_CN",
    alternateLocale: "en_US",
    images: [{ url: "/og/privacy-zh.png", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · 隐私",
    description: "位置留在设备上，不接广告 SDK，不做第三方追踪。",
    images: ["/og/privacy-zh.png"],
  },
};

const COLLECT: [string, string][] = [
  [
    "邮箱地址",
    "只在你付费或订阅邮件通讯时收集。存储在支付服务商（Paddle）和邮件服务商（Buttondown）那里。我们能看到，他们能看到，别人看不到。",
  ],
  [
    "匿名崩溃报告",
    "如果 app 崩溃且你开启了崩溃上报（默认开启，可在设置里关），Sentry 会收到调用栈、设备型号和 iOS 版本。没有邮箱，没有用户 ID，没有位置。",
  ],
  [
    "匿名使用计数",
    "你点了哪些功能、多频繁，聚合数据。没有 IP，没有设备指纹。可在 设置 > 隐私 里关掉。",
  ],
];

const NEVER_COLLECT: [string, string][] = [
  [
    "你的位置",
    "永远留在设备上。地图跑在 Apple MapKit 上，我们看不到。关于你在哪里、去过哪里，什么都不会离开你的手机。",
  ],
  [
    "你保存的体验",
    "你保存、计划、完成过的地点列表，存在你的 iCloud（如果开了 Pro 同步）或者只存在你的设备上。我们没有备份。",
  ],
  [
    "你的语音录音",
    "「问 Solo」的语音输入通过 Apple 的 SFSpeechRecognizer 在设备上转文字。音频永远不会离开你的手机。只有转好的文字才会发给 AI，而且只用于那一次查询。",
  ],
  [
    "通讯录、日历、照片",
    "我们从来不要这些权限。你可以自己查 app 的 Info.plist——权限清单是最小集。",
  ],
  [
    "广告标识符",
    "不用 AdSupport，不用 SKAdNetwork，不接广告网络 SDK。我们没有你的 IDFA，也不想要。",
  ],
];

const THIRD_PARTY: [string, string][] = [
  [
    "Apple",
    "MapKit（地图瓦片）、SFSpeechRecognizer（语音）、StoreKit（支付）。适用 Apple 的隐私政策。",
  ],
  ["Sentry", "只收匿名崩溃报告。服务器在欧盟（法兰克福）。可在设置里关闭。"],
  [
    "Anthropic",
    "AI 推荐用的是 Claude。发送的是你的问题文本——没有位置，没有邮箱，没有设备 ID。Anthropic 不用 API 数据训练模型。",
  ],
  ["Paddle", "支付服务商。处理卡号、税、退款。我们永远看不到你的卡号。"],
];

export default function PrivacyZh() {
  const props = {
    copy: copy.zh,
    locale: "zh" as const,
    homePath: "/zh",
    altPath: "/privacy",
  };
  return (
    <div lang="zh-CN">
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              隐私
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">我们收集什么，不收集什么。</h1>
            <p className="ds-body-xl mt-6 text-fg-muted">
              最近更新：2026 年 7 月。写给人看，不是律师版本。
            </p>
          </Container>
        </Section>

        <Section className="pt-4 pb-16">
          <Container width="narrow">
            <article>
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                我们收集什么
              </h2>
              <dl className="mt-8 divide-y divide-border-subtle">
                {COLLECT.map(([k, v]) => (
                  <div key={k} className="py-6">
                    <dt className="font-display text-[18px] font-medium text-fg-primary">{k}</dt>
                    <dd className="ds-body-md mt-2 text-fg-muted">{v}</dd>
                  </div>
                ))}
              </dl>
            </article>

            <article className="mt-16">
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                我们永远不收集
              </h2>
              <dl className="mt-8 divide-y divide-border-subtle">
                {NEVER_COLLECT.map(([k, v]) => (
                  <div key={k} className="py-6">
                    <dt className="font-display text-[18px] font-medium text-fg-primary">{k}</dt>
                    <dd className="ds-body-md mt-2 text-fg-muted">{v}</dd>
                  </div>
                ))}
              </dl>
            </article>

            <article className="mt-16">
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                第三方服务
              </h2>
              <dl className="mt-8 divide-y divide-border-subtle">
                {THIRD_PARTY.map(([k, v]) => (
                  <div key={k} className="py-6">
                    <dt className="font-display text-[18px] font-medium text-fg-primary">{k}</dt>
                    <dd className="ds-body-md mt-2 text-fg-muted">{v}</dd>
                  </div>
                ))}
              </dl>
            </article>

            <article className="mt-16">
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                你的权利
              </h2>
              <p className="ds-body-lg mt-4 text-fg-muted">
                你可以在 app 内 设置 里删除账号——这会在 30 天内清除你的邮箱和所有服务端同步数据。
                也可以邮件{" "}
                <a className="underline" href="mailto:privacy@solocompass.app">
                  privacy@solocompass.app
                </a>{" "}
                要一份我们持有的全部数据副本，或者立刻删除。 GDPR 和 CCPA
                适用，我们对所有人一视同仁，不只是欧盟和加州居民。
              </p>
            </article>
          </Container>
        </Section>
      </main>
      <Footer {...props} />
    </div>
  );
}
