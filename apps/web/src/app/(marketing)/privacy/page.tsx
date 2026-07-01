import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Privacy · Solo Compass",
  description:
    "What Solo Compass collects, what it doesn't, and where your data lives. Location stays on device. No advertising SDKs. No third-party trackers. Written in plain English.",
  alternates: {
    canonical: `${SITE_URL}/privacy`,
    languages: {
      en: `${SITE_URL}/privacy`,
      "zh-CN": `${SITE_URL}/zh/privacy`,
      "x-default": `${SITE_URL}/privacy`,
    },
  },
  openGraph: {
    type: "article",
    url: `${SITE_URL}/privacy`,
    title: "Solo Compass · Privacy",
    description:
      "Location stays on device. No ads. No third-party trackers. Plain English.",
    images: [{ url: "/og/privacy.png", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · Privacy",
    description: "Location on device. No ads. No trackers.",
    images: ["/og/privacy.png"],
  },
};

const COLLECT: [string, string][] = [
  ["Email address", "Only if you paid or signed up for the newsletter. Stored by our payment processor (Paddle) and email provider (Buttondown). We can see it, they can see it, nobody else can."],
  ["Anonymous crash reports", "If the app crashes and you have crash reporting enabled (default: on, toggle in Settings), Sentry receives a stack trace with device model and iOS version. No email, no user ID, no location."],
  ["Anonymous usage counters", "Which features you tap, how often, aggregated. No IP, no device fingerprint. Toggle off in Settings > Privacy."],
];

const NEVER_COLLECT: [string, string][] = [
  ["Your location", "Stays on device. Ever. The map runs on Apple's MapKit, which we cannot see. Nothing about where you are or where you've been leaves your phone."],
  ["Your saved experiences", "The list of places you've saved, planned, or completed lives in your iCloud (if you enable Pro sync) or nowhere but your device. We don't have a copy."],
  ["Your voice recordings", "The \"Ask Solo\" voice input transcribes on-device via Apple's SFSpeechRecognizer. The audio never leaves your phone. Only the transcribed text is sent to the AI, and only for that one query."],
  ["Contacts, calendar, photos", "We never ask for these permissions. Check the app's Info.plist yourself — the entitlements are minimal."],
  ["Advertising identifiers", "No AdSupport framework. No SKAdNetwork. No SDKs from ad networks. We don't have your IDFA and don't want it."],
];

const THIRD_PARTY: [string, string][] = [
  ["Apple", "MapKit (map tiles), SFSpeechRecognizer (voice), StoreKit (payments). Apple's privacy policy applies."],
  ["Sentry", "Anonymous crash reports only. Located in EU (Frankfurt). Can be disabled in Settings."],
  ["Anthropic", "The AI recommendations use Claude. Your question text is sent — no location, no email, no device ID. Anthropic does not train on API data."],
  ["Paddle", "Payment processor. Handles cards, tax, refunds. We never see your card number."],
];

export default function PrivacyEn() {
  const props = {
    copy: copy.en,
    locale: "en" as const,
    homePath: "/",
    altPath: "/zh/privacy",
  };
  return (
    <>
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              Privacy
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">
              What we collect, and what we don&apos;t.
            </h1>
            <p className="ds-body-xl mt-6 text-fg-muted">
              Last updated: July 2026. Written for humans, not lawyers.
            </p>
          </Container>
        </Section>

        <Section className="pt-4 pb-16">
          <Container width="narrow">
            <article>
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                What we collect
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
                What we never collect
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
                Third parties
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
                Your rights
              </h2>
              <p className="ds-body-lg mt-4 text-fg-muted">
                You can delete your account from Settings inside the app — this
                removes your email and any server-side sync data within 30 days.
                You can also email <a className="underline" href="mailto:privacy@solocompass.app">privacy@solocompass.app</a> to request a copy of everything we hold, or to have it deleted immediately.
                GDPR and CCPA apply and we honor them for everyone, not just EU
                and California residents.
              </p>
            </article>
          </Container>
        </Section>
      </main>
      <Footer {...props} />
    </>
  );
}
