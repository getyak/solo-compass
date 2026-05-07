import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getCompletionsRepo, getExperiencesRepo } from "@/lib/repos";
import {
  cityDisplayName,
  cityEmoji,
  ExperienceRecapCard,
  formatTripDateRange,
  type RecapExperience,
  ShareButton,
  TripStats,
} from "@/components/TripRecap";

// ─── Metadata ──────────────────────────────────────────────────────────────────

interface PageParams {
  readonly handle: string;
  readonly city: string;
}

export async function generateMetadata({
  params,
}: {
  params: Promise<PageParams>;
}): Promise<Metadata> {
  const { handle, city } = await params;
  const cityName = cityDisplayName(city);
  const title = `${handle}'s trip to ${cityName}`;

  return {
    title,
    description: `${handle} explored ${cityName} with Solo Compass. See the experiences they collected.`,
    openGraph: {
      title,
      description: `${handle}'s solo trip to ${cityName}`,
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: `${handle}'s solo trip to ${cityName}`,
    },
  };
}

// ─── Page ──────────────────────────────────────────────────────────────────────

export default async function CityRecapPage({ params }: { params: Promise<PageParams> }) {
  const { handle, city } = await params;

  const completionsRepo = getCompletionsRepo();
  const experiencesRepo = getExperiencesRepo();

  // Check user exists and has a public profile
  const profile = await completionsRepo.getProfile(handle);
  if (!profile) notFound();

  if (!profile.publicProfile) {
    return <PrivateTripPage handle={handle} />;
  }

  // Fetch completions for this city
  const completions = await completionsRepo.findByHandle(handle, city);
  if (completions.length === 0) notFound();

  // Resolve experience details in parallel
  const experiences = await Promise.all(
    completions.map((c) => experiencesRepo.findById(c.experienceId)),
  );

  const items: RecapExperience[] = completions
    .map((completion, i) => {
      const experience = experiences[i];
      if (!experience) return null;
      return { completion, experience };
    })
    .filter((item): item is RecapExperience => item !== null);

  if (items.length === 0) notFound();

  const cityName = cityDisplayName(city);
  const emoji = cityEmoji(city);
  const dateRange = formatTripDateRange(items.map((i) => i.completion));

  // Mapbox static image: plot completed experience locations
  const mapboxToken = process.env.NEXT_PUBLIC_MAPBOX_TOKEN ?? "";
  const staticMapUrl = buildStaticMapUrl(items, mapboxToken, cityName);

  return (
    <main className="min-h-screen bg-paper-cream">
      {/* Hero */}
      <section className="bg-ink-warm px-6 pb-10 pt-12 text-paper-cream">
        <div className="mx-auto max-w-2xl">
          <p className="mb-2 text-sm font-medium uppercase tracking-widest text-paper-cream/50">
            Solo trip recap
          </p>
          <h1 className="mb-2 text-4xl font-bold leading-tight">
            {emoji} {cityName}
          </h1>
          <p className="mb-6 text-lg text-paper-cream/70">
            {handle} · {dateRange}
          </p>
          <TripStats items={items} />
        </div>
      </section>

      {/* Mini-map */}
      {staticMapUrl && (
        <section className="mx-auto max-w-2xl px-4 pt-8">
          <div className="overflow-hidden rounded-2xl shadow-md">
            <img
              src={staticMapUrl}
              alt={`Map of ${handle}'s experiences in ${cityName}`}
              width={800}
              height={320}
              className="h-[200px] w-full object-cover sm:h-[240px]"
            />
          </div>
        </section>
      )}

      {/* Experience cards */}
      <section className="mx-auto max-w-2xl px-4 py-8">
        <h2 className="mb-5 text-xs font-semibold uppercase tracking-widest text-ink-warm/40">
          Experiences collected
        </h2>
        <div className="grid gap-4 sm:grid-cols-2">
          {items.map((item) => (
            <ExperienceRecapCard
              key={item.experience.id}
              item={item}
              handle={handle}
              cityCode={city}
            />
          ))}
        </div>
      </section>

      {/* Footer CTA */}
      <footer className="border-t border-ink-warm/10 bg-paper-cream px-6 py-10 text-center">
        <p className="mb-4 text-sm text-ink-warm/60">Ready to explore {cityName} yourself?</p>
        <a
          href={`/${city}`}
          className="inline-flex items-center gap-2 rounded-xl bg-deep-teal px-6 py-3 text-sm font-semibold text-paper-cream shadow-sm transition hover:bg-deep-teal/90"
        >
          Plan your own {cityName} trip →
        </a>
        <div className="mt-6 flex justify-center">
          <ShareButton
            title={`${handle}'s trip to ${cityName}`}
            url={typeof window !== "undefined" ? window.location.href : ""}
          />
        </div>
      </footer>
    </main>
  );
}

// ─── Private trip fallback ─────────────────────────────────────────────────────

function PrivateTripPage({ handle }: { readonly handle: string }) {
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

// ─── Static Mapbox image ───────────────────────────────────────────────────────

function buildStaticMapUrl(
  items: readonly RecapExperience[],
  token: string,
  _cityName: string,
): string | null {
  if (!token || token === "pk.placeholder_token") return null;
  if (items.length === 0) return null;

  // Pin markers for each experience (max 15 for URL length)
  const pins = items.slice(0, 15).map((item) => {
    const [lng, lat] = item.experience.location.coordinates;
    return `pin-s-circle+2F6B6B(${lng},${lat})`;
  });

  // Compute bounding box and add padding
  const lngs = items.map((i) => i.experience.location.coordinates[0]);
  const lats = items.map((i) => i.experience.location.coordinates[1]);
  const minLng = Math.min(...lngs) - 0.01;
  const maxLng = Math.max(...lngs) + 0.01;
  const minLat = Math.min(...lats) - 0.01;
  const maxLat = Math.max(...lats) + 0.01;

  const overlay = pins.join(",");
  const bbox = `[${minLng},${minLat},${maxLng},${maxLat}]`;

  return `https://api.mapbox.com/styles/v1/mapbox/light-v11/static/${overlay}/${bbox}/800x320@2x?access_token=${token}&padding=40`;
}
