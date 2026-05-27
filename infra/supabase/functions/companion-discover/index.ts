// Edge Function: companion-discover
// Returns anonymized companion posts matching the caller's filters.
//
// US-011: Companion discovery list.
//
// Query params:
//   city_code  - required; ISO city code
//   mode       - optional; "itinerary" | "nearby" — omit for both
//   date_from  - optional; ISO 8601 date (YYYY-MM-DD); filter active_from >= date_from
//   date_to    - optional; ISO 8601 date (YYYY-MM-DD); filter active_to  <= date_to
//   categories - optional; comma-separated ExperienceCategory values
//
// Response: anonymized DiscoverPost[] — no user_id, no exact coords.
//
// Security:
//   - Verifies Supabase JWT (caller must be signed in).
//   - Excludes posts by users who have blocked the caller, or been blocked by the caller.
//   - Only returns posts whose author has visibility != 'off'.
//   - Service-role client used for cross-user queries; RLS bypassed intentionally.
//
// Deploy: `supabase functions deploy companion-discover`
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface DiscoverPost {
  id: string;
  handle: string;     // avatarEmoji only — no real name
  blurb: string;
  categories: string[];
  city_code: string;
  mode: string;
  active_from: string | null;
  active_to: string | null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "Authorization, Content-Type" },
    });
  }
  if (req.method !== "GET") {
    return json({ error: "method not allowed" }, 405);
  }

  // 1. Verify JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer /i, "");
  if (!jwt) return json({ error: "missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // User-scoped client to verify the token
  const userClient = createClient(supabaseUrl, jwt, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "unauthorized" }, 401);

  const callerId = user.id;

  // 2. Parse query params
  const url = new URL(req.url);
  const cityCode = url.searchParams.get("city_code");
  if (!cityCode) return json({ error: "city_code is required" }, 400);

  const mode = url.searchParams.get("mode");        // optional
  const dateFrom = url.searchParams.get("date_from");  // optional
  const dateTo = url.searchParams.get("date_to");      // optional
  const categoriesParam = url.searchParams.get("categories"); // optional, comma-sep

  // 3. Service-role client for cross-user queries
  const svc = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // 4. Collect blocked user IDs (bidirectional)
  const { data: blocksOut } = await svc
    .from("companion_blocks")
    .select("blocked_id")
    .eq("blocker_id", callerId);

  const { data: blocksIn } = await svc
    .from("companion_blocks")
    .select("blocker_id")
    .eq("blocked_id", callerId);

  const blockedIds = new Set<string>([
    ...(blocksOut ?? []).map((r: { blocked_id: string }) => r.blocked_id),
    ...(blocksIn ?? []).map((r: { blocker_id: string }) => r.blocker_id),
  ]);

  // 5. Fetch profiles with visibility != 'off', excluding blocked users
  const { data: visibleProfiles, error: profileErr } = await svc
    .from("companion_profiles")
    .select("user_id, avatar_emoji")
    .neq("visibility", "off");

  if (profileErr) return json({ error: "profile lookup failed" }, 500);

  const visibleUserIds = (visibleProfiles ?? [])
    .map((p: { user_id: string; avatar_emoji: string }) => p.user_id)
    .filter((uid: string) => uid !== callerId && !blockedIds.has(uid));

  if (visibleUserIds.length === 0) {
    return json({ posts: [] }, 200);
  }

  const emojiByUserId = Object.fromEntries(
    (visibleProfiles ?? []).map((p: { user_id: string; avatar_emoji: string }) => [p.user_id, p.avatar_emoji])
  );

  // 6. Query companion_posts
  let query = svc
    .from("companion_posts")
    .select("id, author_id, blurb, categories, city_code, mode, active_from, active_to")
    .eq("city_code", cityCode)
    .eq("is_deleted", false)
    .in("author_id", visibleUserIds);

  if (mode) query = query.eq("mode", mode);
  if (dateFrom) query = query.gte("active_from", dateFrom);
  if (dateTo) query = query.lte("active_to", dateTo);

  if (categoriesParam) {
    const cats = categoriesParam.split(",").map((c) => c.trim()).filter(Boolean);
    if (cats.length > 0) {
      // Filter posts where categories array overlaps with requested categories
      query = query.overlaps("categories", cats);
    }
  }

  const { data: posts, error: postsErr } = await query
    .order("created_at", { ascending: false })
    .limit(50);

  if (postsErr) return json({ error: "posts lookup failed" }, 500);

  // 7. Build anonymized response — no user_id, no coordinates
  const result: DiscoverPost[] = (posts ?? []).map((p: {
    id: string;
    author_id: string;
    blurb: string;
    categories: string[];
    city_code: string;
    mode: string;
    active_from: string | null;
    active_to: string | null;
  }) => ({
    id: p.id,
    handle: emojiByUserId[p.author_id] ?? "🧭",
    blurb: p.blurb,
    categories: p.categories ?? [],
    city_code: p.city_code,
    mode: p.mode,
    active_from: p.active_from ?? null,
    active_to: p.active_to ?? null,
  }));

  return json({ posts: result }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
