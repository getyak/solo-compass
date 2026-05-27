-- US-019: reporter_weight downranking in companion discovery.
--
-- Rules:
--   • reporter_weight starts at 1.0 for all users.
--   • Each accepted report against a user reduces their weight by 0.2 (floor 0.0).
--   • Users with reporter_weight < 0.3 are excluded from discovery entirely.
--   • The companion-discover Edge Function orders results by reporter_weight DESC
--     (higher-trust authors surface first).
--
-- This migration adds reporter_weight to companion_profiles so the Edge Function
-- can sort and filter without a separate join to auth.users.

begin;

alter table public.companion_profiles
  add column if not exists reporter_weight numeric not null default 1.0
  check (reporter_weight >= 0.0 and reporter_weight <= 1.0);

-- Index so the Edge Function's ORDER BY reporter_weight DESC is efficient.
create index if not exists companion_profiles_reporter_weight_idx
  on public.companion_profiles(reporter_weight desc);

-- When a companion_report is inserted, reduce the target user's reporter_weight
-- on their companion_profile (if one exists). Each report costs 0.2, floored at 0.
create or replace function sc_downrank_on_report()
  returns trigger
  language plpgsql
  security definer
as $$
begin
  update public.companion_profiles
  set reporter_weight = greatest(0.0, reporter_weight - 0.2)
  where user_id = NEW.target_user_id;
  return NEW;
end;
$$;

drop trigger if exists companion_report_downrank on public.companion_reports;

create trigger companion_report_downrank
  after insert on public.companion_reports
  for each row execute function sc_downrank_on_report();

commit;
