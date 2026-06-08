-- Solo Compass — Friend-request Realtime subscription (US-018)
--
-- Lets a recipient see new friend requests live (no manual refresh). The iOS
-- FriendService subscribes to postgres INSERT events on `public.friend_requests`
-- filtered by `recipient_id=eq.<self>`; this migration makes those events
-- actually broadcast.
--
-- Two pieces are required for Realtime on a table:
--   1. The table must be a member of the `supabase_realtime` publication so
--      WAL changes are streamed to the Realtime server.
--   2. RLS on the table is honoured by Realtime — a row only reaches a client
--      whose JWT passes the SELECT policy. The `friend_requests participant-select`
--      policy (0008_friends.sql) already grants `auth.uid() = recipient_id`, so
--      the recipient — and only the recipient — receives their own request rows.
--
-- `REPLICA IDENTITY FULL` ensures the RLS check has every column available when
-- evaluating which subscribers may receive the change (matching the pattern used
-- for chat_messages).
--
-- Idempotent: re-running is safe (publication membership guarded by catalog
-- lookup; replica identity is a no-op when already set).

begin;

-- Ship the full row image so Realtime's RLS filter can evaluate recipient_id.
alter table public.friend_requests replica identity full;

-- Add friend_requests to the realtime publication only if not already a member.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'friend_requests'
  ) then
    alter publication supabase_realtime add table public.friend_requests;
  end if;
exception
  when undefined_object then
    -- The supabase_realtime publication doesn't exist in this environment
    -- (e.g. a bare local Postgres without the Supabase Realtime extension).
    -- Nothing to do — Realtime simply won't be available there.
    null;
end$$;

commit;
