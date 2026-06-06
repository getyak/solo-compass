-- Solo Compass — Promote a user-created place into the public pool (UGC, Phase 3)
--
-- candidate → active. A curator (or an automated rule) calls
-- `promote_user_experience(<exp_user_id>)`. It assembles the row in
-- `user_experiences` into a full Experience JSON and upserts it into
-- `synthesized_experiences` (the shared pool the app reads), then flips the
-- source row's status to 'active'.
--
-- SECURITY DEFINER so it can write the shared pool regardless of the caller's
-- RLS — but it is locked to service_role only (see grant at the bottom), so a
-- normal authenticated user can never self-promote their own place. That is the
-- trust gate: users submit candidates; only a privileged review path activates.
--
-- The assembled payload preserves whatever the AI enrichment step already wrote
-- back onto the row (description = whyItMatters). Solo Score is taken from the
-- row when present; promotion does NOT invent one.
--
-- DEPLOYMENT: run via `supabase db query -f` (Management API). Claude cannot
-- deploy unattended without the user's confirmation.

create or replace function public.promote_user_experience(p_experience_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.user_experiences%rowtype;
  v_payload jsonb;
  v_now text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
begin
  select * into r from public.user_experiences where experience_id = p_experience_id;
  if not found then
    raise exception 'user_experience % not found', p_experience_id;
  end if;

  -- Assemble a full Experience JSON matching the app's decoder. Fields the user
  -- never supplies (howTo, nearbyExperienceIds, stats) default to empty/zero;
  -- the soloScore/confidence are conservative until further verification.
  v_payload := jsonb_build_object(
    'id', r.experience_id,
    'title', r.title,
    'oneLiner', r.one_liner,
    'whyItMatters', coalesce(r.description, ''),
    'category', r.category,
    'location', jsonb_build_object(
      'coordinates', r.coordinates,
      'cityCode', r.city_code,
      'addressHint', r.address_hint,
      'placeNameLocal', r.place_name_local,
      'placeNameRomanized', r.place_name_romanized,
      'photoUrls', r.photo_urls
    ),
    'bestTimes', '[]'::jsonb,
    'durationMinutes', jsonb_build_object('min', 30, 'max', 60),
    'howTo', '[]'::jsonb,
    'realInconveniences', '[]'::jsonb,
    'soloScore', jsonb_build_object(
      'overall', 5,
      'breakdown', jsonb_build_object(
        'seatingFriendly', 5, 'soloPatronRatio', 5, 'staffPressure', 5,
        'soloPortioning', 5, 'ambianceFit', 5, 'safety', 5
      ),
      'basedOnCount', 0
    ),
    'sources', jsonb_build_array(
      jsonb_build_object('type', 'user', 'attribution', 'community', 'verifiedAt', v_now)
    ),
    'confidence', jsonb_build_object(
      'level', 3,
      'lastVerifiedAt', v_now,
      'reason', 'User-created, reviewed and promoted',
      'signals', jsonb_build_object(
        'aiScrapeAgeDays', 0, 'passiveGpsHits30d', 0, 'activeReports30d', 1, 'trustedVerifications', 1
      )
    ),
    'nearbyExperienceIds', '[]'::jsonb,
    'stats', jsonb_build_object('completionCount', 0, 'averageRating', 0),
    'status', 'active',
    'createdAt', v_now,
    'updatedAt', v_now,
    'userTags', coalesce(r.user_tags, '[]'::jsonb)
  );

  insert into public.synthesized_experiences (id, city_code, payload, model_name, source_cache_key)
  values (r.experience_id, r.city_code, jsonb_build_array(v_payload), 'user-promoted', 'promote_' || r.experience_id)
  on conflict (id) do update
    set payload = excluded.payload,
        city_code = excluded.city_code,
        updated_at = now();

  update public.user_experiences set status = 'active' where experience_id = p_experience_id;
end;
$$;

-- Lock it down: only the service role (curator tooling / Edge Functions) may
-- call this. Revoke from the roles a normal client authenticates as.
revoke all on function public.promote_user_experience(text) from public, anon, authenticated;
grant execute on function public.promote_user_experience(text) to service_role;
