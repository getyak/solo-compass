// RLS smoke test — US-028.
//
// Verifies four invariants of the schema's row-level-security posture:
//   1. anon cannot read user_favorites of any user
//   2. user A authenticated cannot read user B's user_favorites
//   3. anon CAN read synthesized_experiences (public-read)
//   4. service-role CAN write synthesized_experiences (write boundary)
//
// Run: `deno run --allow-net --allow-env test_rls.ts`
// Requires env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Exits 0 on PASS, 1 on FAIL.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing env. Set SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY.");
  Deno.exit(1);
}

const failures: string[] = [];
function assert(cond: unknown, label: string) {
  if (!cond) failures.push(label);
  console.log(`${cond ? "PASS" : "FAIL"} — ${label}`);
}

const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// --- 1. anon cannot read user_favorites ------------------------------------

{
  const { data, error } = await anonClient.from("user_favorites").select("experience_id").limit(1);
  // RLS denies — Supabase returns empty array (no rows match policy), not an error.
  assert(
    !error && Array.isArray(data) && data.length === 0,
    "anon select on user_favorites returns 0 rows (RLS denies)",
  );
}

// --- 2. cross-user isolation on user_favorites -----------------------------

const userA = await anonClient.auth.signInAnonymously();
const userB = await anonClient.auth.signInAnonymously();
assert(!!userA.data.user, "user A anonymous sign-in succeeded");
assert(!!userB.data.user, "user B anonymous sign-in succeeded");

if (userA.data.user && userB.data.user) {
  // user A favorites an experience as themselves.
  const aClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  await aClient.auth.setSession({
    access_token: userA.data.session!.access_token,
    refresh_token: userA.data.session!.refresh_token,
  });
  const { error: insertErr } = await aClient
    .from("user_favorites")
    .insert({ user_id: userA.data.user.id, experience_id: "exp_test_rls_fav" });
  assert(!insertErr, `user A insert favorite succeeds: ${insertErr?.message ?? "ok"}`);

  // user B should NOT see user A's favorite.
  const bClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  await bClient.auth.setSession({
    access_token: userB.data.session!.access_token,
    refresh_token: userB.data.session!.refresh_token,
  });
  const { data: leakCheck } = await bClient
    .from("user_favorites")
    .select("experience_id")
    .eq("user_id", userA.data.user.id);
  assert(
    Array.isArray(leakCheck) && leakCheck.length === 0,
    "user B cannot see user A's favorites (RLS isolation)",
  );

  // Cleanup with service role.
  await serviceClient
    .from("user_favorites")
    .delete()
    .or(`user_id.eq.${userA.data.user.id},user_id.eq.${userB.data.user.id}`);
  await serviceClient.auth.admin.deleteUser(userA.data.user.id).catch(() => {});
  await serviceClient.auth.admin.deleteUser(userB.data.user.id).catch(() => {});
}

// --- 3. anon CAN read synthesized_experiences ------------------------------

{
  const { error } = await anonClient.from("synthesized_experiences").select("id").limit(1);
  assert(!error, `anon select on synthesized_experiences succeeds: ${error?.message ?? "ok"}`);
}

// --- 4. service-role CAN write synthesized_experiences ---------------------

{
  const probeId = `exp_test_${Date.now()}`;
  const { error: insertErr } = await serviceClient.from("synthesized_experiences").insert({
    id: probeId,
    city_code: "test-city",
    payload: {},
    model_name: "test",
    source_cache_key: "test-key",
  });
  assert(!insertErr, `service-role insert succeeds: ${insertErr?.message ?? "ok"}`);

  await serviceClient.from("synthesized_experiences").delete().eq("id", probeId);
}

// --- Result ----------------------------------------------------------------

if (failures.length > 0) {
  console.error(`\n${failures.length} failure(s):`);
  for (const f of failures) console.error(`  - ${f}`);
  Deno.exit(1);
} else {
  console.log("\nAll RLS invariants hold.");
  Deno.exit(0);
}
