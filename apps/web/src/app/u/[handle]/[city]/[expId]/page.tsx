import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getCompletionsRepo, getExperiencesRepo } from "@/lib/repos";
import { categoryEmoji, categoryLabel } from "@/lib/category";
import { cityDisplayName } from "@/components/TripRecap";

// ─── Metadata ──────────────────────────────────────────────────────────────────

interface PageParams {
  readonly handle: string;
  readonly city: string;
  readonly expId: string;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<PageParams>;
}): Promise<Metadata> {
  const { handle, city, expId } = await params;
  const experiencesRepo = getExperiencesRepo();
  const experience = await experiencesRepo.findById(expId);
  if (!experience) return {};

  const cityName = cityDisplayName(city);
  const title = `${experience.title} — ${handle} in ${cityName}`;

  return {
    title,
    description: experience.oneLiner,
    openGraph: {
      title,
      description: experience.oneLiner,
      type: "article",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: experience.oneLiner,
    },
  };
}

// ─── Page ──────────────────────────────────────────────────────────────────────

export default async function SingleExperienceRecapPage({
  params,
}: {
  params: Promise<PageParams>;
}) {
  const { handle, city, expId } = await params;

  const completionsRepo = getCompletionsRepo();
  const experiencesRepo = getExperiencesRepo();

  // Check user exists and has a public profile
  const profile = await completionsRepo.getProfile(handle);
  if (!profile) notFound();

  if (!profile.publicProfile) {
    return <PrivateExperiencePage handle={handle} />;
  }

  const [experience, completions] = await Promise.all([
    experiencesRepo.findById(expId),
    completionsRepo.findByHandle(handle, city),
  ]);

  if (!experience) notFound();

  const completion = completions.find((c) => c.experienceId === expId);
  if (!completion) notFound();

  const cityName = cityDisplayName(city);
  const completedDate = new Date(completion.completedAt).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  return (
    <main className="min-h-screen bg-paper-cream">
      {/* Back link */}
      <div className="mx-auto max-w-2xl px-4 pt-6">
        <a
          href={`/u/${handle}/${city}`}
          className="inline-flex items-center gap-1.5 text-sm text-deep-teal hover:underline"
        >
          ← {handle}'s trip to {cityName}
        </a>
      </div>

      {/* Photo placeholder */}
      <div className="mx-auto mt-4 max-w-2xl px-4">
        <div className="flex h-52 items-center justify-center rounded-2xl bg-muted-road/30 sm:h-64">
          <span className="text-6xl" aria-hidden="true">
            {categoryEmoji[experience.category]}
          </span>
        </div>
      </div>

      {/* Experience detail */}
      <article className="mx-auto max-w-2xl px-4 py-6">
        {/* Category + date + rating */}
        <div className="mb-2 flex flex-wrap items-center gap-2 text-xs font-medium uppercase tracking-wide text-deep-teal">
          <span>
            {categoryEmoji[experience.category]} {categoryLabel[experience.category]}
          </span>
          <span className="text-ink-warm/30">·</span>
          <span className="text-ink-warm/50">{completedDate}</span>
          {completion.rating && (
            <>
              <span className="text-ink-warm/30">·</span>
              <span className="text-warm-amber">{"★".repeat(completion.rating)}</span>
            </>
          )}
        </div>

        <h1 className="mb-3 text-2xl font-bold leading-snug text-ink-warm sm:text-3xl">
          {experience.title}
        </h1>

        <p className="mb-6 text-base leading-relaxed text-ink-warm/80">{experience.oneLiner}</p>

        {/* Personal note */}
        {completion.note && (
          <blockquote className="mb-6 rounded-xl border-l-4 border-deep-teal/40 bg-white px-5 py-4 text-sm italic leading-relaxed text-ink-warm/80 shadow-sm">
            "{completion.note}"
            <footer className="mt-2 text-xs not-italic text-ink-warm/50">— {handle}</footer>
          </blockquote>
        )}

        {/* Why it matters */}
        <Section title="Why it matters">
          <p className="text-sm leading-relaxed text-ink-warm/80">{experience.whyItMatters}</p>
        </Section>

        {/* How to */}
        <Section title="How to do this">
          <ol className="space-y-2 text-sm leading-relaxed text-ink-warm/80">
            {experience.howTo.map((step) => (
              <li key={step.order} className="flex gap-3">
                <span className="flex-shrink-0 font-mono text-ink-warm/40">{step.order}.</span>
                <span>{step.text}</span>
              </li>
            ))}
          </ol>
        </Section>

        {/* Solo score */}
        <Section title="Solo score">
          <div className="flex items-baseline gap-2">
            <span className="text-2xl font-semibold text-ink-warm">
              {experience.soloScore.overall.toFixed(0)}
            </span>
            <span className="text-xs text-ink-warm/60">
              / 10 · based on {experience.soloScore.basedOnCount} reports
            </span>
          </div>
          {experience.soloScore.hint && (
            <p className="mt-1 text-sm text-ink-warm/70">{experience.soloScore.hint}</p>
          )}
        </Section>

        {/* Real inconveniences */}
        {experience.realInconveniences.length > 0 && (
          <Section title="Real inconveniences">
            <ul className="space-y-1.5 text-sm leading-relaxed text-ink-warm/80">
              {experience.realInconveniences.map((r, i) => (
                <li key={i} className="flex gap-2">
                  <span className="text-ink-warm/40">•</span>
                  <span>
                    <span className="text-xs uppercase tracking-wide text-warm-amber">
                      {r.category}
                    </span>{" "}
                    {r.text}
                  </span>
                </li>
              ))}
            </ul>
          </Section>
        )}

        {/* CTA */}
        <div className="mt-8 rounded-2xl bg-ink-warm px-6 py-6 text-center text-paper-cream">
          <p className="mb-4 text-sm text-paper-cream/70">Want to do this in {cityName}?</p>
          <a
            href={`/${city}`}
            className="inline-flex items-center gap-2 rounded-xl bg-deep-teal px-5 py-2.5 text-sm font-semibold text-paper-cream shadow-sm transition hover:bg-deep-teal/90"
          >
            Open map in {cityName} →
          </a>
        </div>
      </article>

      {/* Footer nav */}
      <footer className="border-t border-ink-warm/10 px-6 py-8 text-center text-sm text-ink-warm/50">
        <a href={`/u/${handle}/${city}`} className="hover:text-ink-warm hover:underline">
          ← See all of {handle}'s {cityName} experiences
        </a>
      </footer>
    </main>
  );
}

// ─── Private fallback ──────────────────────────────────────────────────────────

function PrivateExperiencePage({ handle }: { readonly handle: string }) {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-paper-cream px-6 text-center">
      <span className="mb-4 text-5xl" aria-hidden="true">
        🔒
      </span>
      <h1 className="mb-2 text-2xl font-bold text-ink-warm">This trip is private</h1>
      <p className="mb-6 max-w-sm text-sm text-ink-warm/60">
        {handle} has chosen to keep their experiences private.
      </p>
      <a
        href="/"
        className="rounded-xl bg-deep-teal px-5 py-2.5 text-sm font-semibold text-paper-cream transition hover:bg-deep-teal/90"
      >
        Explore Solo Compass
      </a>
    </main>
  );
}

// ─── Section ───────────────────────────────────────────────────────────────────

function Section({
  title,
  children,
}: {
  readonly title: string;
  readonly children: React.ReactNode;
}) {
  return (
    <section className="mb-5">
      <h2 className="mb-1.5 text-xs font-semibold uppercase tracking-wider text-ink-warm/40">
        {title}
      </h2>
      {children}
    </section>
  );
}
