import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { ButtonLink, Eyebrow, Section } from "@/components/marketing/primitives";

const SITE_URL = "https://solocompass.app";
const APP_STORE_URL = "https://apps.apple.com/app/solo-compass/id0000000000";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Download · Solo Compass for iOS",
  description:
    "Solo Compass is available on the App Store for iPhone. Requires iOS 17.0 or later. Free tier available with 3 AI cross-references per day. No card needed to try.",
  alternates: {
    canonical: `${SITE_URL}/download`,
    languages: {
      en: `${SITE_URL}/download`,
      "zh-CN": `${SITE_URL}/download`,
      "x-default": `${SITE_URL}/download`,
    },
  },
  openGraph: {
    type: "website",
    url: `${SITE_URL}/download`,
    title: "Download Solo Compass for iOS",
    description: "iPhone. iOS 17+. Free tier, no card needed. Available on the App Store.",
    images: [{ url: "/og/download.png", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Download Solo Compass for iOS",
    description: "iPhone. iOS 17+. On the App Store.",
    images: ["/og/download.png"],
  },
};

const REQUIREMENTS: [string, string][] = [
  ["Device", "iPhone (iOS 17.0 or later)"],
  ["Size", "~46 MB download"],
  ["Languages", "English, 简体中文"],
  ["Region", "Available worldwide"],
  ["Price", "Free · $29 lifetime · $50/year"],
];

export default function DownloadPage() {
  const props = {
    copy: copy.en,
    locale: "en" as const,
    homePath: "/",
    altPath: "/zh",
  };
  return (
    <>
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-12">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              Download
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">Get Solo Compass on iPhone.</h1>
            <p className="ds-body-xl mt-6 text-fg-muted">
              Free to try. No card, no email. Pay only when Free stops being enough.
            </p>
            <div className="mt-10 flex justify-center">
              <ButtonLink href={APP_STORE_URL} variant="primary">
                Download on the App Store
              </ButtonLink>
            </div>
          </Container>
        </Section>

        <Section className="pb-24">
          <Container width="narrow">
            <article>
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                Requirements
              </h2>
              <dl className="mt-8 divide-y divide-border-subtle">
                {REQUIREMENTS.map(([k, v]) => (
                  <div key={k} className="flex justify-between py-4">
                    <dt className="font-body text-[15px] font-medium text-fg-primary">{k}</dt>
                    <dd className="font-body text-[15px] text-fg-muted">{v}</dd>
                  </div>
                ))}
              </dl>
            </article>

            <article className="mt-16">
              <h2 className="font-display text-[28px] font-medium text-fg-primary md:text-[32px]">
                Not on Android yet.
              </h2>
              <p className="ds-body-lg mt-4 text-fg-muted">
                Solo Compass is iOS-only for now. The app is built with SwiftUI and MapKit — porting
                to Android is not a straight line, and a bad Android version would be worse than
                none. If you want to be notified when it lands, email{" "}
                <a className="underline" href="mailto:hello@solocompass.app">
                  hello@solocompass.app
                </a>{" "}
                with subject &ldquo;Android&rdquo;.
              </p>
            </article>
          </Container>
        </Section>
      </main>
      <Footer {...props} />
    </>
  );
}
