-- Solo Compass — Companion Mode (US-007 + US-008)
--
-- US-007 (Phase 1): `itineraries` table — device-to-cloud sync.
-- US-008 (Phase 2): companion_profiles, companion_posts, companion_requests,
--   conversations, chat_messages, companion_reports, companion_blocks.
--
-- All tables gated by FF_COMPANION on the iOS client.

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- US-007: itineraries
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.itineraries (
  id                  text          primary key,            -- ItineraryId.rawValue (UUID string)
  user_id             uuid          not null references auth.users(id) on delete cascade,
  owner_id            text          not null,               -- "local" until linked to auth.uid()
  title               text          not null,
  city_code           text          not null,
  start_date          text          not null,               -- ISO 8601 date (YYYY-MM-DD)
  end_date            text          not null,               -- ISO 8601 date (YYYY-MM-DD)
  experience_ids      jsonb         not null default '[]'::jsonb,
  note                text,
  open_to_companions  boolean       not null default false,
  is_deleted          boolean       not null default false,
  device_id           text,
  created_at          timestamptz   not null default now(),
  updated_at          timestamptz   not null default now()
);

create index if not exists itineraries_user_idx      on public.itineraries(user_id);
create index if not exists itineraries_updated_idx   on public.itineraries(user_id, updated_at desc);

create trigger itineraries_touch_updated_at
  before update on public.itineraries
  for each row execute function sc_touch_updated_at();

alter table public.itineraries enable row level security;

create policy "itineraries self-select" on public.itineraries
  for select using (auth.uid() = user_id);

create policy "itineraries self-insert" on public.itineraries
  for insert with check (auth.uid() = user_id);

create policy "itineraries self-update" on public.itineraries
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "itineraries self-delete" on public.itineraries
  for delete using (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: companion_profiles
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.companion_profiles (
  id            text        primary key,       -- CompanionProfileId.rawValue
  user_id       uuid        not null unique references auth.users(id) on delete cascade,
  avatar_emoji  text        not null default '🧭',
  bio           text        not null default '',
  languages     jsonb       not null default '[]'::jsonb,  -- ISO code strings
  -- off | itinerary_only | nearby_and_itinerary
  visibility    text        not null default 'off'
                              check (visibility in ('off','itinerary_only','nearby_and_itinerary')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger companion_profiles_touch_updated_at
  before update on public.companion_profiles
  for each row execute function sc_touch_updated_at();

alter table public.companion_profiles enable row level security;

create policy "companion_profiles self-select" on public.companion_profiles
  for select using (auth.uid() = user_id);

create policy "companion_profiles public-select" on public.companion_profiles
  for select using (visibility <> 'off');

create policy "companion_profiles self-insert" on public.companion_profiles
  for insert with check (auth.uid() = user_id);

create policy "companion_profiles self-update" on public.companion_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "companion_profiles self-delete" on public.companion_profiles
  for delete using (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: companion_posts
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.companion_posts (
  id            text        primary key,       -- CompanionPostId.rawValue
  author_id     uuid        not null references auth.users(id) on delete cascade,
  -- itinerary | nearby
  mode          text        not null check (mode in ('itinerary','nearby')),
  itinerary_id  text        references public.itineraries(id) on delete set null,
  blurb         text        not null,
  categories    jsonb       not null default '[]'::jsonb,
  city_code     text        not null,
  active_from   text,                          -- ISO 8601 date (YYYY-MM-DD)
  active_to     text,                          -- ISO 8601 date (YYYY-MM-DD)
  is_deleted    boolean     not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists companion_posts_author_idx  on public.companion_posts(author_id);
create index if not exists companion_posts_city_idx    on public.companion_posts(city_code, updated_at desc);

create trigger companion_posts_touch_updated_at
  before update on public.companion_posts
  for each row execute function sc_touch_updated_at();

alter table public.companion_posts enable row level security;

create policy "companion_posts self-select" on public.companion_posts
  for select using (auth.uid() = author_id);

create policy "companion_posts public-select" on public.companion_posts
  for select using (
    is_deleted = false
    and exists (
      select 1 from public.companion_profiles cp
      where cp.user_id = author_id and cp.visibility <> 'off'
    )
  );

create policy "companion_posts self-insert" on public.companion_posts
  for insert with check (auth.uid() = author_id);

create policy "companion_posts self-update" on public.companion_posts
  for update using (auth.uid() = author_id) with check (auth.uid() = author_id);

create policy "companion_posts self-delete" on public.companion_posts
  for delete using (auth.uid() = author_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: companion_requests
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.companion_requests (
  id            text        primary key,       -- CompanionRequestId.rawValue
  post_id       text        not null references public.companion_posts(id) on delete cascade,
  requester_id  uuid        not null references auth.users(id) on delete cascade,
  recipient_id  uuid        not null references auth.users(id) on delete cascade,
  -- pending | accepted | declined | withdrawn
  status        text        not null default 'pending'
                              check (status in ('pending','accepted','declined','withdrawn')),
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists companion_requests_requester_idx on public.companion_requests(requester_id);
create index if not exists companion_requests_recipient_idx on public.companion_requests(recipient_id);

create trigger companion_requests_touch_updated_at
  before update on public.companion_requests
  for each row execute function sc_touch_updated_at();

alter table public.companion_requests enable row level security;

create policy "companion_requests participant-select" on public.companion_requests
  for select using (auth.uid() = requester_id or auth.uid() = recipient_id);

create policy "companion_requests requester-insert" on public.companion_requests
  for insert with check (auth.uid() = requester_id);

create policy "companion_requests participant-update" on public.companion_requests
  for update
  using (auth.uid() = requester_id or auth.uid() = recipient_id)
  with check (auth.uid() = requester_id or auth.uid() = recipient_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: conversations
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.conversations (
  id                text        primary key,   -- ConversationId.rawValue
  request_id        text        not null unique references public.companion_requests(id) on delete cascade,
  participant_ids   jsonb       not null default '[]'::jsonb,
  last_message_at   timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create trigger conversations_touch_updated_at
  before update on public.conversations
  for each row execute function sc_touch_updated_at();

alter table public.conversations enable row level security;

create policy "conversations participant-select" on public.conversations
  for select using (
    participant_ids @> to_jsonb(auth.uid()::text)
  );

create policy "conversations participant-insert" on public.conversations
  for insert with check (
    participant_ids @> to_jsonb(auth.uid()::text)
  );

create policy "conversations participant-update" on public.conversations
  for update
  using (participant_ids @> to_jsonb(auth.uid()::text))
  with check (participant_ids @> to_jsonb(auth.uid()::text));

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: chat_messages
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.chat_messages (
  id              text        primary key,     -- ChatMessageId.rawValue
  conversation_id text        not null references public.conversations(id) on delete cascade,
  sender_id       uuid        not null references auth.users(id) on delete cascade,
  body            text        not null,
  read_at         timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists chat_messages_conversation_idx on public.chat_messages(conversation_id, created_at asc);

alter table public.chat_messages enable row level security;

create policy "chat_messages participant-select" on public.chat_messages
  for select using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and c.participant_ids @> to_jsonb(auth.uid()::text)
    )
  );

create policy "chat_messages sender-insert" on public.chat_messages
  for insert with check (auth.uid() = sender_id);

create policy "chat_messages recipient-update-read_at" on public.chat_messages
  for update using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and c.participant_ids @> to_jsonb(auth.uid()::text)
    )
  ) with check (auth.uid() <> sender_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: companion_reports
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.companion_reports (
  id              text        primary key,     -- CompanionReportId.rawValue
  reporter_id     uuid        not null references auth.users(id) on delete cascade,
  target_user_id  uuid        not null references auth.users(id) on delete cascade,
  -- spam | harassment | inappropriate_content | fake_profile | other
  reason          text        not null
                    check (reason in ('spam','harassment','inappropriate_content','fake_profile','other')),
  details         text,
  created_at      timestamptz not null default now()
);

create index if not exists companion_reports_reporter_idx     on public.companion_reports(reporter_id);
create index if not exists companion_reports_target_user_idx  on public.companion_reports(target_user_id);

alter table public.companion_reports enable row level security;

create policy "companion_reports self-insert" on public.companion_reports
  for insert with check (auth.uid() = reporter_id);

create policy "companion_reports self-select" on public.companion_reports
  for select using (auth.uid() = reporter_id);

-- ──────────────────────────────────────────────────────────────────────────────
-- US-008: companion_blocks
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.companion_blocks (
  blocker_id  uuid        not null references auth.users(id) on delete cascade,
  blocked_id  uuid        not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

create index if not exists companion_blocks_blocker_idx on public.companion_blocks(blocker_id);

alter table public.companion_blocks enable row level security;

create policy "companion_blocks self-select" on public.companion_blocks
  for select using (auth.uid() = blocker_id);

create policy "companion_blocks self-insert" on public.companion_blocks
  for insert with check (auth.uid() = blocker_id);

create policy "companion_blocks self-delete" on public.companion_blocks
  for delete using (auth.uid() = blocker_id);

commit;
