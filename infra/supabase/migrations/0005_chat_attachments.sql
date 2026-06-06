-- Solo Compass — Chat Attachments (chat-experience-upgrade Batch A)
--
-- Adds full-chain attachment support to companion DMs and LLM chat:
--   1. `chat_messages.attachments` jsonb column — mirrors TS `ChatMessage.attachments`
--      (array of ChatAttachment; avoids a join table, aligns with `attachments?`).
--   2. Private storage bucket `chat-media` for the binary payloads.
--   3. storage.objects RLS so ONLY conversation participants can upload (insert)
--      and download (select) objects under their conversation prefix.
--
-- Object path convention: `{conversationId}/{messageId}/{attachmentId}-{fileName}`,
-- so `(storage.foldername(name))[1]` is the conversationId.
--
-- DEPLOYMENT: run via `supabase db push` or paste into the Supabase SQL editor.
-- Claude cannot deploy this — the user must. The `chat-media` bucket can
-- alternatively be created in the Supabase dashboard (Storage → New bucket,
-- name `chat-media`, public = off); the RLS policies below still apply.

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- 1. chat_messages.attachments
-- ──────────────────────────────────────────────────────────────────────────────

alter table public.chat_messages
  add column if not exists attachments jsonb;

-- ──────────────────────────────────────────────────────────────────────────────
-- 2. Private storage bucket `chat-media`
-- ──────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- ──────────────────────────────────────────────────────────────────────────────
-- 3. storage.objects RLS — conversation participants only
--
-- The first path segment is the conversationId. A user may read/write an object
-- only when they are a participant of that conversation. This prevents one user
-- from reading another user's attachments.
-- ──────────────────────────────────────────────────────────────────────────────

create policy "chat-media participant-insert" on storage.objects
  for insert with check (
    bucket_id = 'chat-media'
    and exists (
      select 1 from public.conversations c
      where c.id = (storage.foldername(name))[1]
        and c.participant_ids @> to_jsonb(auth.uid()::text)
    )
  );

create policy "chat-media participant-select" on storage.objects
  for select using (
    bucket_id = 'chat-media'
    and exists (
      select 1 from public.conversations c
      where c.id = (storage.foldername(name))[1]
        and c.participant_ids @> to_jsonb(auth.uid()::text)
    )
  );

commit;
