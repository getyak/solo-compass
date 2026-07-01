import type { Metadata } from "next";
import { copy } from "@/components/marketing/copy";
import { Footer, MarketingNav } from "@/components/marketing/sections";
import { Container } from "@/components/marketing/Container";
import { Eyebrow, Section } from "@/components/marketing/primitives";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Manifesto · Solo Compass",
  description:
    "Why Solo Compass exists. A short manifesto on solo travel, honest AI, and why we chose the hard path — no ads, no tracking, no VC — even when it costs us reach.",
  alternates: {
    canonical: `${SITE_URL}/manifesto`,
    languages: {
      en: `${SITE_URL}/manifesto`,
      "zh-CN": `${SITE_URL}/zh/manifesto`,
      "x-default": `${SITE_URL}/manifesto`,
    },
  },
  openGraph: {
    type: "article",
    url: `${SITE_URL}/manifesto`,
    title: "Solo Compass · Manifesto",
    description:
      "A short manifesto on solo travel, honest AI, and why we chose no ads, no tracking, no VC.",
    images: [{ url: "/og/manifesto.png", width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · Manifesto",
    description: "Why we chose no ads, no tracking, no VC.",
    images: ["/og/manifesto.png"],
  },
};

const PARAGRAPHS_EN: { heading: string; body: string }[] = [
  {
    heading: "The map should be the point.",
    body: "Every other travel app pushes you into feeds, lists, and \"recommended for you\" pages. The map is a tab. In Solo Compass, the map is the app. The first thing you see is where you are and what's around you — filtered, ranked, honest. Not because we're minimalist; because that's what a solo traveler actually needs at 4 PM in a strange city.",
  },
  {
    heading: "Experience, not place.",
    body: "\"Blue Bottle Coffee\" is a place. \"A quiet corner where I can read for two hours without a barista rushing me\" is an experience. Places are what maps store. Experiences are what people remember. We built the core data model around Experience — with mood, best times, sensory notes, and solo-friendliness — so the app can answer real questions, not point at pins.",
  },
  {
    heading: "AI shows its work.",
    body: "We use AI to filter and explain, never to replace your judgment. Every ranking shows the sources it drew from — Wikimedia, OSM, official pages, verified reviews. Every recommendation shows its confidence. When the model is uncertain, it says so. When two sources disagree, both are shown. Solo travel is high-stakes; opaque AI is not acceptable.",
  },
  {
    heading: "No ads. No tracking. Ever.",
    body: "The moment an app has ads, its incentives split from yours. It has to hold attention. It has to inflate ratings for paying partners. It has to know where you are and what you buy. Solo Compass makes money one way: you paid for it. If we ever break that promise, we owe every Lifetime buyer a full refund. This is written into our terms.",
  },
  {
    heading: "Built in Kyoto. Answerable to you.",
    body: "One person. No VC pressure to grow at all costs. No board to answer to. That means no dark patterns, no A/B tests to squeeze conversion, no growth hacks that treat you as a metric. When you email us, a human writes back — usually within a day, sometimes with a photo of the specific street in question.",
  },
  {
    heading: "For the person who booked the flight alone.",
    body: "Not the influencer, not the group traveler, not the person doing a bucket-list checklist. The person who saved for months, chose to go alone, and wants the trip to be their own — not filtered through someone else's algorithm. If that's you, we made this for you.",
  },
];

export default function ManifestoEn() {
  const props = {
    copy: copy.en,
    locale: "en" as const,
    homePath: "/",
    altPath: "/zh/manifesto",
  };
  return (
    <>
      <MarketingNav {...props} />
      <main id="main">
        <Section className="pt-24 md:pt-32 pb-8">
          <Container width="narrow" className="text-center">
            <Eyebrow dot="accent" className="justify-center">
              Manifesto
            </Eyebrow>
            <h1 className="ds-display-xl mt-6 font-display">
              A map for people who travel alone.
            </h1>
            <p className="ds-body-xl mt-6 text-fg-muted">
              Six things we believe. Written before the first line of code, and
              still true.
            </p>
          </Container>
        </Section>

        <Section className="pt-4 pb-24">
          <Container width="narrow">
            <div className="space-y-16">
              {PARAGRAPHS_EN.map((p, i) => (
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
    </>
  );
}
