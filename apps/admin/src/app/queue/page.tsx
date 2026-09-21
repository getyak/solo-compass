import { createSupabaseServerClient } from "@/lib/supabase/server";
import Link from "next/link";

const PAGE_SIZE = 50;
const CLAIM_TTL_MS = 30 * 60 * 1000;

interface QueueRow {
  id: string;
  title: string;
  city_code: string;
  category: string;
  source_count: number;
  confidence_level: number;
  created_at: string;
  claimed_by: string | null;
  claimed_at: string | null;
}

interface PageProps {
  searchParams: Promise<{
    page?: string;
    city?: string;
    source_type?: string | string[];
    weight_min?: string;
    weight_max?: string;
  }>;
}

export default async function QueuePage({ searchParams }: PageProps) {
  const params = await searchParams;

  const page = Math.max(1, parseInt(params.page ?? "1", 10));
  const cityFilter = params.city ?? "";
  const sourceTypes = Array.isArray(params.source_type)
    ? params.source_type
    : params.source_type
      ? [params.source_type]
      : [];
  const weightMin = params.weight_min ? parseInt(params.weight_min, 10) : undefined;
  const weightMax = params.weight_max ? parseInt(params.weight_max, 10) : undefined;

  const supabase = await createSupabaseServerClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const currentEmail = user?.email ?? null;

  // Fetch distinct city codes for the dropdown
  const { data: cityRows } = await supabase
    .from("experiences")
    .select("city_code")
    .eq("status", "candidate")
    .order("city_code");

  const cities = Array.from(new Set((cityRows ?? []).map((r) => r.city_code).filter(Boolean)));

  let query = supabase
    .from("experiences")
    .select(
      `
      id,
      title,
      city_code,
      category,
      confidence_level,
      created_at,
      sources!inner(source_type, weight),
      editor_queue(claimed_by, claimed_at)
    `,
      { count: "exact" },
    )
    .eq("status", "candidate");

  if (cityFilter) {
    query = query.eq("city_code", cityFilter);
  }

  if (weightMin !== undefined) {
    query = query.gte("confidence_level", weightMin);
  }
  if (weightMax !== undefined) {
    query = query.lte("confidence_level", weightMax);
  }

  query = query
    .order("confidence_level", { ascending: false })
    .order("created_at", { ascending: true });

  const offset = (page - 1) * PAGE_SIZE;
  query = query.range(offset, offset + PAGE_SIZE - 1);

  const { data: rawRows, count, error } = await query;

  if (error) {
    return <ErrorView message={error.message} />;
  }

  const now = Date.now();

  const rows: QueueRow[] = (rawRows ?? []).map((r) => {
    const srcs = Array.isArray(r.sources) ? r.sources : [];
    const filteredSrcs = sourceTypes.length
      ? srcs.filter((s: { source_type: string }) => sourceTypes.includes(s.source_type))
      : srcs;
    const sourceCount = filteredSrcs.length;
    const totalWeight = filteredSrcs.reduce(
      (sum: number, s: { weight: number }) => sum + s.weight,
      0,
    );

    // editor_queue is a one-to-one relation returned as an array
    const queueRows = Array.isArray(r.editor_queue)
      ? r.editor_queue
      : r.editor_queue
        ? [r.editor_queue]
        : [];
    const queueRow = queueRows[0] as
      { claimed_by: string | null; claimed_at: string | null } | undefined;
    const claimedAt = queueRow?.claimed_at ? new Date(queueRow.claimed_at).getTime() : null;
    const isActive = claimedAt !== null && now - claimedAt < CLAIM_TTL_MS;

    return {
      id: r.id as string,
      title: r.title as string,
      city_code: r.city_code as string,
      category: r.category as string,
      source_count: sourceCount,
      confidence_level: totalWeight || (r.confidence_level as number),
      created_at: r.created_at as string,
      claimed_by: isActive ? (queueRow?.claimed_by ?? null) : null,
      claimed_at: isActive ? (queueRow?.claimed_at ?? null) : null,
    };
  });

  const filteredRows = sourceTypes.length ? rows.filter((r) => r.source_count > 0) : rows;

  const totalPages = Math.ceil((count ?? 0) / PAGE_SIZE);

  return (
    <div className="min-h-screen bg-gray-950 text-gray-100">
      <header className="border-b border-gray-800 px-6 py-4">
        <h1 className="text-xl font-semibold">Review Queue</h1>
        <p className="text-sm text-gray-400 mt-1">{count ?? 0} candidates awaiting review</p>
      </header>

      <div className="px-6 py-4">
        <FilterBar
          cities={cities}
          cityFilter={cityFilter}
          sourceTypes={sourceTypes}
          weightMin={weightMin}
          weightMax={weightMax}
        />

        {filteredRows.length === 0 ? (
          <p className="text-gray-400 mt-8 text-center">No candidates match your filters.</p>
        ) : (
          <>
            <QueueTable rows={filteredRows} currentEmail={currentEmail} />
            <Pagination page={page} totalPages={totalPages} searchParams={params} />
          </>
        )}
      </div>
    </div>
  );
}

function FilterBar({
  cities,
  cityFilter,
  sourceTypes,
  weightMin,
  weightMax,
}: {
  cities: string[];
  cityFilter: string;
  sourceTypes: string[];
  weightMin?: number;
  weightMax?: number;
}) {
  const allSourceTypes = ["wikivoyage", "osm", "google_places"];

  return (
    <form method="GET" className="flex flex-wrap gap-4 mb-6 items-end">
      <div className="flex flex-col gap-1">
        <label className="text-xs text-gray-400 uppercase tracking-wide">City</label>
        <select
          name="city"
          defaultValue={cityFilter}
          className="bg-gray-800 border border-gray-700 rounded px-3 py-2 text-sm text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
        >
          <option value="">All Cities</option>
          {cities.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-xs text-gray-400 uppercase tracking-wide">Source Types</label>
        <div className="flex gap-3">
          {allSourceTypes.map((st) => (
            <label key={st} className="flex items-center gap-1.5 text-sm cursor-pointer">
              <input
                type="checkbox"
                name="source_type"
                value={st}
                defaultChecked={sourceTypes.includes(st)}
                className="rounded border-gray-600 bg-gray-800 text-blue-500 focus:ring-blue-500"
              />
              <span className="text-gray-300">{st.replace("_", " ")}</span>
            </label>
          ))}
        </div>
      </div>

      <div className="flex flex-col gap-1">
        <label className="text-xs text-gray-400 uppercase tracking-wide">Confidence (Weight)</label>
        <div className="flex items-center gap-2">
          <input
            type="number"
            name="weight_min"
            placeholder="Min"
            defaultValue={weightMin}
            min={0}
            max={5}
            className="w-16 bg-gray-800 border border-gray-700 rounded px-2 py-2 text-sm text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
          />
          <span className="text-gray-500">–</span>
          <input
            type="number"
            name="weight_max"
            placeholder="Max"
            defaultValue={weightMax}
            min={0}
            max={5}
            className="w-16 bg-gray-800 border border-gray-700 rounded px-2 py-2 text-sm text-gray-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
          />
        </div>
      </div>

      <button
        type="submit"
        className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded text-sm font-medium transition-colors"
      >
        Apply
      </button>

      <a
        href="/queue"
        className="px-4 py-2 bg-gray-800 hover:bg-gray-700 rounded text-sm font-medium transition-colors"
      >
        Reset
      </a>
    </form>
  );
}

function QueueTable({ rows, currentEmail }: { rows: QueueRow[]; currentEmail: string | null }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-800">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-800 bg-gray-900">
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              Title
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              City
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              Sources
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              Weight
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              Age
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase tracking-wide">
              Status
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-800">
          {rows.map((row) => {
            const isClaimedByOther = row.claimed_by !== null && row.claimed_by !== currentEmail;
            return (
              <tr
                key={row.id}
                className={`transition-colors ${isClaimedByOther ? "opacity-40" : "hover:bg-gray-900"}`}
              >
                <td className="px-4 py-3">
                  <Link
                    href={`/queue/${row.id}`}
                    className="text-blue-400 hover:text-blue-300 font-medium"
                  >
                    {row.title}
                  </Link>
                </td>
                <td className="px-4 py-3 text-gray-400 font-mono text-xs">
                  {row.city_code || "—"}
                </td>
                <td className="px-4 py-3 text-gray-300">{row.source_count}</td>
                <td className="px-4 py-3">
                  <WeightBadge level={row.confidence_level} />
                </td>
                <td className="px-4 py-3 text-gray-400 text-xs">{formatAge(row.created_at)}</td>
                <td className="px-4 py-3">
                  {row.claimed_by !== null && (
                    <ClaimedBadge
                      claimedBy={row.claimed_by}
                      isMe={row.claimed_by === currentEmail}
                    />
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function ClaimedBadge({ claimedBy, isMe }: { claimedBy: string; isMe: boolean }) {
  if (isMe) {
    return (
      <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-900 text-green-300">
        Claimed by you
      </span>
    );
  }
  return (
    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-900 text-yellow-300">
      Claimed by {claimedBy}
    </span>
  );
}

function WeightBadge({ level }: { level: number }) {
  const colors: Record<number, string> = {
    0: "bg-gray-700 text-gray-400",
    1: "bg-red-900 text-red-300",
    2: "bg-orange-900 text-orange-300",
    3: "bg-yellow-900 text-yellow-300",
    4: "bg-green-900 text-green-300",
    5: "bg-emerald-900 text-emerald-300",
  };
  const cls = colors[Math.min(level, 5)] ?? colors[0];
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${cls}`}>
      {level}/5
    </span>
  );
}

function Pagination({
  page,
  totalPages,
  searchParams,
}: {
  page: number;
  totalPages: number;
  searchParams: Record<string, string | string[] | undefined>;
}) {
  if (totalPages <= 1) return null;

  function buildHref(p: number) {
    const sp = new URLSearchParams();
    sp.set("page", String(p));
    if (searchParams.city) sp.set("city", String(searchParams.city));
    if (searchParams.weight_min) sp.set("weight_min", String(searchParams.weight_min));
    if (searchParams.weight_max) sp.set("weight_max", String(searchParams.weight_max));
    const sts = Array.isArray(searchParams.source_type)
      ? searchParams.source_type
      : searchParams.source_type
        ? [searchParams.source_type]
        : [];
    sts.forEach((st) => sp.append("source_type", st));
    return `/queue?${sp.toString()}`;
  }

  return (
    <div className="flex items-center justify-between mt-4 text-sm text-gray-400">
      <span>
        Page {page} of {totalPages}
      </span>
      <div className="flex gap-2">
        {page > 1 && (
          <Link
            href={buildHref(page - 1)}
            className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded transition-colors text-gray-200"
          >
            Previous
          </Link>
        )}
        {page < totalPages && (
          <Link
            href={buildHref(page + 1)}
            className="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 rounded transition-colors text-gray-200"
          >
            Next
          </Link>
        )}
      </div>
    </div>
  );
}

function ErrorView({ message }: { message: string }) {
  return (
    <div className="min-h-screen bg-gray-950 text-gray-100 flex items-center justify-center">
      <div className="text-center">
        <p className="text-red-400 font-medium">Failed to load queue</p>
        <p className="text-gray-500 text-sm mt-1">{message}</p>
      </div>
    </div>
  );
}

function formatAge(isoDate: string): string {
  const now = Date.now();
  const then = new Date(isoDate).getTime();
  const diffMs = now - then;
  const days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  if (days === 0) return "today";
  if (days === 1) return "1d ago";
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  if (months === 1) return "1mo ago";
  if (months < 12) return `${months}mo ago`;
  const years = Math.floor(months / 12);
  return `${years}y ago`;
}
