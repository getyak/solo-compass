import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav, Pricing } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";
import { HomeJsonLd } from "../../_seo";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Pricing · Solo Compass",
  description:
    "$29 one-time lifetime, or $50 yearly. No ads. No data selling. No subscription bloat. Free tier to try before you buy.",
  alternates: {
    canonical: `${SITE_URL}/pricing`,
    languages: {
      en: `${SITE_URL}/pricing`,
      "zh-CN": `${SITE_URL}/zh/pricing`,
      "x-default": `${SITE_URL}/pricing`,
    },
  },
  openGraph: {
    url: `${SITE_URL}/pricing`,
    title: "Solo Compass · Pricing",
    description: "$29 lifetime or $50 yearly. Honest pricing, no ads.",
    images: [{ url: "/og/pricing.png", width: 1200, height: 630 }],
  },
};

const FAQ_EN = [
  {
    q: "Why is Lifetime cheaper than Yearly?",
    a: "Because Lifetime locks in what exists today; Yearly gets everything we ship in the future. Craft and Fastmail work the same way. Neither is a mistake — pick based on your relationship with new features.",
  },
  {
    q: "What's in Free vs Pro?",
    a: "Free gives you the map, city guides, and 3 AI cross-references per day. Pro removes the daily cap and unlocks cross-city routes, Rituals authoring, iCloud sync, and print export.",
  },
  {
    q: "Do you offer a student discount?",
    a: "Yes — 50% off Yearly ($25) with a .edu email or UNiDAYS verification. Rolls out in Phase 1.5.",
  },
  {
    q: "Will you ever run ads?",
    a: "No. Ever. If we ever change this, we'll refund every Lifetime purchase in full.",
  },
  {
    q: "Do you sell my data?",
    a: "No. Your location never leaves your phone. See our privacy page for the four tables of what we do and don't collect.",
  },
  {
    q: "Can I try before I buy?",
    a: "Yes. Free tier is genuinely useful, not a demo. Download from the App Store, use it for a week, then decide.",
  },
];

export default function PricingPage() {
  const props = {
    copy: copy.en,
    locale: "en" as const,
    homePath: "/",
    altPath: "/zh",
  };
  return (
    <>
      <HomeJsonLd locale="en" />
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              {copy.en.pricing.eyebrow}
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">{copy.en.pricing.title}</h1>
            <p className="ds-body-xl mt-6">{copy.en.pricing.sub}</p>
          </Container>
        </Section>
        <Pricing {...props} />

        <Section className="border-t border-border-subtle/50">
          <Container width="narrow">
            <Eyebrow dot="sun">Frequently asked</Eyebrow>
            <h2 className="ds-display-md mt-6 font-display">
              Honest answers to what people actually ask.
            </h2>
            <dl className="mt-12 divide-y divide-border-subtle">
              {FAQ_EN.map((item, i) => (
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
    </>
  );
}
