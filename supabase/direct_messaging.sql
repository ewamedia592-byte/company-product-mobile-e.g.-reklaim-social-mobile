begin;
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- Chat notification configuration helper
-- ---------------------------------------------------------------------------

create table if not exists public.chat_notify_config (
    id boolean primary key default true,
    worker_url text,
    worker_auth text
);

alter table public.chat_notify_config enable row level security;

drop policy if exists "service role manage notify config" on public.chat_notify_config;
create policy "service role manage notify config"
    on public.chat_notify_config
    for all using (auth.role() = 'service_role')
    with check (auth.role() = 'service_role');

drop policy if exists "block public notify config" on public.chat_notify_config;
create policy "block public notify config"
    on public.chat_notify_config
    for select using (false);

create or replace function public.chat_get_notify_config()
returns table(worker_url text, worker_auth text)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
      select cnc.worker_url, cnc.worker_auth
        from public.chat_notify_config cnc
       where cnc.id = true;
end;
$$;

-- ---------------------------------------------------------------------------
-- Core tables
-- ---------------------------------------------------------------------------

alter table public.public_profiles
  add column if not exists messaging_enabled boolean not null default true;

alter table public.public_profiles
  add column if not exists cover_url text,
  add column if not exists cover_type text check (cover_type in ('image','video')),
  add column if not exists headline text,
  add column if not exists website_url text,
  add column if not exists contact_email text,
  add column if not exists contact_phone text,
  add column if not exists call_to_action text,
  add column if not exists call_to_action_url text;

create table if not exists public.chat_threads (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    is_group boolean not null default false,
    title text,
    avatar_url text,
    created_by uuid references auth.users(id)
);

create index if not exists idx_chat_threads_created_by
  on public.chat_threads(created_by)
  where created_by is not null;

create table if not exists public.chat_thread_participants (
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    joined_at timestamptz not null default now(),
    last_read_at timestamptz,
    last_typing_at timestamptz,
    muted_until timestamptz,
    display_name text,
    avatar_url text,
    role text not null default 'member',
    invited_by uuid references auth.users(id),
    visible_from timestamptz not null default timestamp 'epoch',
    primary key (thread_id, user_id)
);

create index if not exists idx_chat_thread_participants_user
  on public.chat_thread_participants(user_id);

create table if not exists public.chat_group_invitations (
    id uuid primary key default gen_random_uuid(),
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    invited_user_id uuid not null references auth.users(id) on delete cascade,
    invited_by uuid not null references auth.users(id),
    created_at timestamptz not null default now(),
    expires_at timestamptz,
    status text not null default 'pending'
);

create index if not exists idx_chat_group_invites_thread
  on public.chat_group_invitations(thread_id);
create index if not exists idx_chat_group_invites_invited_user
  on public.chat_group_invitations(invited_user_id);
create index if not exists idx_chat_group_invites_invited_by
  on public.chat_group_invitations(invited_by);

alter table public.chat_thread_participants
  add column if not exists last_typing_at timestamptz;

alter table public.chat_thread_participants
  add column if not exists muted_until timestamptz;

alter table public.chat_threads
  add column if not exists is_group boolean not null default false;

alter table public.chat_threads
  add column if not exists title text;

alter table public.chat_threads
  add column if not exists avatar_url text;

alter table public.chat_threads
  add column if not exists created_by uuid references auth.users(id);

create table if not exists public.chat_messages (
    id uuid primary key default gen_random_uuid(),
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    sender_id uuid not null references auth.users(id) on delete cascade,
    body text,
    message_type text not null default 'text',
    attachment_url text,
    attachment_thumb_url text,
    attachment_metadata jsonb,
    deleted_at timestamptz,
    deleted_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    edited_at timestamptz
);

create index if not exists idx_chat_messages_thread_time
    on public.chat_messages(thread_id, created_at);
create index if not exists idx_chat_messages_sender
    on public.chat_messages(sender_id);

alter table public.chat_thread_participants
  add column if not exists last_typing_at timestamptz;

alter table public.chat_messages
  add column if not exists message_type text not null default 'text';

alter table public.chat_messages
  add column if not exists attachment_url text;

alter table public.chat_messages
  add column if not exists attachment_thumb_url text;

alter table public.chat_messages
  add column if not exists attachment_metadata jsonb;

alter table public.chat_messages
  add column if not exists deleted_at timestamptz;

alter table public.chat_messages
  add column if not exists deleted_by uuid references auth.users(id);

alter table public.chat_messages
  alter column body drop not null;

alter table public.chat_thread_participants
  add column if not exists role text default 'member';

alter table public.chat_thread_participants
  add column if not exists invited_by uuid references auth.users(id);

alter table public.chat_thread_participants
  add column if not exists visible_from timestamptz not null default timestamp 'epoch';

create table if not exists public.chat_message_reactions (
    id uuid primary key default gen_random_uuid(),
    message_id uuid not null references public.chat_messages(id) on delete cascade,
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    reaction text not null,
    created_at timestamptz not null default now()
);

create unique index if not exists idx_chat_message_reactions_unique
  on public.chat_message_reactions(message_id, user_id);

create index if not exists idx_chat_message_reactions_thread
  on public.chat_message_reactions(thread_id);
create index if not exists idx_chat_message_reactions_user
  on public.chat_message_reactions(user_id);

create table if not exists public.chat_message_mentions (
    message_id uuid not null references public.chat_messages(id) on delete cascade,
    mentioned_user_id uuid not null references auth.users(id) on delete cascade,
    handled boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (message_id, mentioned_user_id)
);

do $$
begin
    if exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'chat_message_mentions'
           and column_name = 'user_id'
    ) then
        alter table public.chat_message_mentions
          rename column user_id to mentioned_user_id;
    end if;
end$$;

alter table public.chat_message_mentions
  add column if not exists mentioned_user_id uuid
    references auth.users(id) on delete cascade;

alter table public.chat_message_mentions
  add column if not exists handled boolean not null default false;

alter table public.chat_message_mentions
  add column if not exists created_at timestamptz not null default now();

create index if not exists idx_chat_message_mentions_user
  on public.chat_message_mentions(mentioned_user_id);

grant select, insert, update on public.chat_message_mentions to service_role;
grant select on public.chat_message_mentions to authenticated;

create table if not exists public.chat_guest_access (
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    guest_id uuid not null references auth.users(id) on delete cascade,
    granted_by uuid not null references auth.users(id) on delete cascade,
    added_at timestamptz not null default now(),
    expires_at timestamptz not null,
    revoked_at timestamptz,
    primary key (thread_id, guest_id)
);

create index if not exists idx_chat_guest_access_expiry
  on public.chat_guest_access(expires_at);
create index if not exists idx_chat_guest_access_guest
  on public.chat_guest_access(guest_id);

create table if not exists public.chat_temp_guest_invites (
    id uuid primary key default gen_random_uuid(),
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    guest_id uuid not null references auth.users(id) on delete cascade,
    requested_by uuid not null references auth.users(id) on delete cascade,
    duration_minutes integer not null check (duration_minutes between 1 and 4320),
    status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled','expired')),
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    expires_at timestamptz
);

create index if not exists idx_chat_temp_guest_invites_thread
  on public.chat_temp_guest_invites(thread_id);
create index if not exists idx_chat_temp_guest_invites_guest
  on public.chat_temp_guest_invites(guest_id);
create index if not exists idx_chat_temp_guest_invites_requested_by
  on public.chat_temp_guest_invites(requested_by)
  where requested_by is not null;

create unique index if not exists chat_temp_guest_invites_pending_key
  on public.chat_temp_guest_invites(thread_id, guest_id)
  where status = 'pending';

alter table public.chat_group_invitations enable row level security;
alter table public.chat_message_reactions enable row level security;
alter table public.chat_message_mentions enable row level security;
alter table public.chat_guest_access enable row level security;
alter table public.chat_temp_guest_invites enable row level security;

drop policy if exists "Participants view invitations"
    on public.chat_group_invitations;

create policy "Participants view invitations"
    on public.chat_group_invitations
    for select using (
        auth.uid() = invited_user_id
        or exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_group_invitations.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Admins manage invitations"
    on public.chat_group_invitations;

create policy "Admins manage invitations"
    on public.chat_group_invitations
    for all using (
        exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_group_invitations.thread_id
               and tp.user_id = auth.uid()
               and tp.role in ('owner','admin')
        )
    )
    with check (
        exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_group_invitations.thread_id
               and tp.user_id = auth.uid()
               and tp.role in ('owner','admin')
        )
    );

drop policy if exists "Participants view reactions"
    on public.chat_message_reactions;

create policy "Participants view reactions"
    on public.chat_message_reactions
    for select using (
        exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_message_reactions.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Participants react to messages"
    on public.chat_message_reactions;

create policy "Participants react to messages"
    on public.chat_message_reactions
    for insert with check (
        auth.uid() = user_id
        and exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_message_reactions.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Participants update reactions"
    on public.chat_message_reactions;

create policy "Participants update reactions"
    on public.chat_message_reactions
    for update using (
        auth.uid() = user_id
    )
    with check (
        auth.uid() = user_id
        and exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_message_reactions.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Participants remove reactions"
    on public.chat_message_reactions;

create policy "Participants remove reactions"
    on public.chat_message_reactions
    for delete using (
        auth.uid() = user_id
        and exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_message_reactions.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Participants view guest access"
    on public.chat_guest_access;

create policy "Participants view guest access"
    on public.chat_guest_access
    for select using (
        auth.uid() = guest_id
        or exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_guest_access.thread_id
               and tp.user_id = auth.uid()
        )
    );

drop policy if exists "Participants view temp invites"
    on public.chat_temp_guest_invites;

create policy "Participants view temp invites"
    on public.chat_temp_guest_invites
    for select using (
        auth.uid() = guest_id
        or exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = chat_temp_guest_invites.thread_id
               and tp.user_id = auth.uid()
        )
    );

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.chat_threads enable row level security;
alter table public.chat_thread_participants enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "Users can view threads they participate in"
    on public.chat_threads;

create policy "Users can view threads they participate in"
    on public.chat_threads
    for select using (
        exists (
            select 1
            from public.chat_thread_participants p
            where p.thread_id = chat_threads.id
              and p.user_id = auth.uid()
        )
    );

drop policy if exists "Participants can view messages"
    on public.chat_messages;

create policy "Participants can view messages"
    on public.chat_messages
    for select using (
        exists (
            select 1
            from public.chat_thread_participants p
            where p.thread_id = chat_messages.thread_id
              and p.user_id = auth.uid()
              and chat_messages.created_at >= coalesce(p.visible_from, timestamp 'epoch')
        )
    );

drop policy if exists "Participants can insert messages"
    on public.chat_messages;

create policy "Participants can insert messages"
    on public.chat_messages
    for insert with check (
        auth.uid() = sender_id
        and exists (
            select 1
            from public.chat_thread_participants p
            where p.thread_id = chat_messages.thread_id
              and p.user_id = auth.uid()
        )
    );

drop policy if exists "Participants can update their messages"
    on public.chat_messages;

create policy "Participants can update their messages"
    on public.chat_messages
    for update using (
        auth.uid() = sender_id
        and deleted_at is null
        and exists (
            select 1
            from public.chat_thread_participants p
            where p.thread_id = chat_messages.thread_id
              and p.user_id = auth.uid()
        )
    ) with check (
        auth.uid() = sender_id
        and exists (
            select 1
            from public.chat_thread_participants p
            where p.thread_id = chat_messages.thread_id
              and p.user_id = auth.uid()
        )
    );

drop policy if exists "Participants can update their read state"
    on public.chat_thread_participants;

drop policy if exists "Participants can update their state"
    on public.chat_thread_participants;

create policy "Participants can update their state"
    on public.chat_thread_participants
    for update using (user_id = auth.uid())
    with check (user_id = auth.uid());

drop function if exists public.chat_is_thread_admin(uuid);

create or replace function public.chat_is_thread_admin(p_thread_id uuid)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
      from public.chat_thread_participants m
     where m.thread_id = p_thread_id
       and m.user_id = auth.uid()
       and m.role in ('owner','admin')
  );
$$;

drop policy if exists "Admins manage participant records"
    on public.chat_thread_participants;

create policy "Admins manage participant records"
    on public.chat_thread_participants
    for update using (public.chat_is_thread_admin(chat_thread_participants.thread_id))
    with check (public.chat_is_thread_admin(chat_thread_participants.thread_id));

drop policy if exists "Admins remove participants"
    on public.chat_thread_participants;

create policy "Admins remove participants"
    on public.chat_thread_participants
    for delete using (public.chat_is_thread_admin(chat_thread_participants.thread_id));

drop policy if exists "Participants can view participant records"
    on public.chat_thread_participants;

drop function if exists public.chat_is_member(uuid);

create or replace function public.chat_is_member(p_thread_id uuid)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
as $$
  select exists (
    select 1
      from public.chat_thread_participants m
     where m.thread_id = p_thread_id
       and m.user_id = auth.uid()
  );
$$;

create policy "Participants can view participant records"
    on public.chat_thread_participants
    for select using (
        auth.uid() = user_id
        or public.chat_is_member(chat_thread_participants.thread_id)
    );

-- ---------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------

create or replace function public.chat_upsert_participant(
    p_thread_id uuid,
    p_user_id uuid,
    p_role text default 'member',
    p_invited_by uuid default null,
    p_visible_from timestamptz default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.chat_thread_participants as tp (
        thread_id,
        user_id,
        display_name,
        avatar_url,
        role,
        invited_by,
        visible_from
    )
    values (
        p_thread_id,
        p_user_id,
        (select coalesce(username, 'Anonymous') from public.public_profiles where id = p_user_id),
        (select avatar_url from public.public_profiles where id = p_user_id),
        coalesce(p_role, 'member'),
        p_invited_by,
        coalesce(
            p_visible_from,
            case when coalesce(p_role, 'member') = 'guest' then now() else timestamp 'epoch' end
        )
    )
    on conflict (thread_id, user_id) do update
        set display_name = excluded.display_name,
            avatar_url = excluded.avatar_url,
            role = coalesce(excluded.role, tp.role),
            invited_by = coalesce(excluded.invited_by, tp.invited_by),
            visible_from = coalesce(
                nullif(excluded.visible_from, timestamp 'epoch'),
                tp.visible_from
            );
end;
$$;

create or replace function public.chat_set_messaging_enabled(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    result_row public.public_profiles%rowtype;
    next_enabled boolean := coalesce(p_enabled, true);
begin
    if v_user_id is null then
        raise exception 'Not authenticated';
    end if;

    update public.public_profiles
       set messaging_enabled = next_enabled,
           updated_at = now()
     where id = v_user_id
     returning * into result_row;

    if result_row.id is null then
        insert into public.public_profiles (id, messaging_enabled, updated_at)
        values (v_user_id, next_enabled, now())
        on conflict (id) do update
            set messaging_enabled = excluded.messaging_enabled,
                updated_at = now()
        returning * into result_row;
    end if;

    return jsonb_build_object(
        'id', result_row.id,
        'messaging_enabled', result_row.messaging_enabled,
        'updated_at', result_row.updated_at
    );
end;
$$;

-- ---------------------------------------------------------------------------
-- Shared call media state & catalog
-- ---------------------------------------------------------------------------

create table if not exists public.call_shared_media_state (
    session_id text primary key,
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    media_type text not null check (media_type in ('music','video')),
    media_id text not null,
    media_title text,
    media_url text,
    media_thumbnail text,
    duration_ms integer,
    state text not null check (state in ('playing','paused','stopped')) default 'stopped',
    position_ms integer not null default 0,
    initiated_by uuid references auth.users(id) on delete set null,
    updated_at timestamptz not null default now(),
    last_command text,
    latency_ms integer
);

alter table public.call_shared_media_state enable row level security;

drop policy if exists "call shared media participants" on public.call_shared_media_state;
create policy "call shared media participants"
    on public.call_shared_media_state
    for all
    using (public.chat_is_member(thread_id))
    with check (public.chat_is_member(thread_id));

create table if not exists public.call_shared_media_events (
    id uuid primary key default gen_random_uuid(),
    session_id text not null,
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    media_id text,
    command text not null check (command in ('start','pause','resume','seek','stop','error')),
    state text,
    position_ms integer,
    latency_ms integer,
    created_at timestamptz not null default now(),
    payload jsonb
);

alter table public.call_shared_media_events enable row level security;

drop policy if exists "shared media events readable" on public.call_shared_media_events;
create policy "shared media events readable"
    on public.call_shared_media_events
    for select using (
        exists (
            select 1
              from public.chat_thread_participants tp
             where tp.thread_id = call_shared_media_events.thread_id
               and tp.user_id = auth.uid()
        ) or auth.role() = 'service_role'
    );

drop policy if exists "shared media events manage" on public.call_shared_media_events;
create policy "shared media events manage"
    on public.call_shared_media_events
    for all using (auth.role() = 'service_role')
    with check (auth.role() = 'service_role');

create table if not exists public.call_shared_media_catalog (
    id text primary key,
    media_type text not null check (media_type in ('music', 'video')),
    title text not null,
    description text,
    media_url text not null,
    thumbnail_url text,
    duration_ms integer,
    source text,
    is_active boolean not null default true,
    metadata jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists idx_call_shared_media_type
  on public.call_shared_media_catalog (media_type, is_active)
  where is_active;

create or replace function public.call_shared_media_catalog_updated()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_call_shared_media_catalog_updated on public.call_shared_media_catalog;
create trigger trg_call_shared_media_catalog_updated
    before update on public.call_shared_media_catalog
    for each row
    execute function public.call_shared_media_catalog_updated();

alter table public.call_shared_media_catalog enable row level security;

drop policy if exists "shared media catalog select" on public.call_shared_media_catalog;
create policy "shared media catalog select"
    on public.call_shared_media_catalog
    for select
    using (is_active and (auth.role() = 'authenticated' or auth.role() = 'service_role'));

drop policy if exists "shared media catalog manage" on public.call_shared_media_catalog;
create policy "shared media catalog manage"
    on public.call_shared_media_catalog
    for all
    using (auth.role() = 'service_role')
    with check (auth.role() = 'service_role');

drop function if exists public.call_shared_media_set_state(text, uuid, text, text, text, text, text, integer, text, integer);
drop function if exists public.call_shared_media_set_state(text, uuid, text, text, text, text, text, integer, text, integer, text, integer);

create or replace function public.call_shared_media_set_state(
    p_session_id text,
    p_thread_id uuid,
    p_media_type text,
    p_media_id text,
    p_media_title text,
    p_media_url text,
    p_state text,
    p_position_ms integer,
    p_media_thumbnail text default null,
    p_duration_ms integer default null,
    p_command text default null,
    p_latency_ms integer default null
) returns public.call_shared_media_state
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user uuid := auth.uid();
    v_row public.call_shared_media_state;
    normalized_state text := lower(coalesce(p_state, 'stopped'));
    normalized_command text := lower(coalesce(p_command, p_state, 'stop'));
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = 'P0001';
    end if;

    if not public.chat_is_member(p_thread_id) then
        raise exception 'not authorized for this thread' using errcode = 'P0001';
    end if;

    insert into public.call_shared_media_state as s (
        session_id,
        thread_id,
        media_type,
        media_id,
        media_url,
        media_title,
        media_thumbnail,
        duration_ms,
        state,
        position_ms,
        initiated_by,
        updated_at,
        last_command,
        latency_ms
    ) values (
        p_session_id,
        p_thread_id,
        lower(p_media_type),
        p_media_id,
        p_media_url,
        p_media_title,
        p_media_thumbnail,
        nullif(p_duration_ms, 0),
        normalized_state,
        greatest(0, coalesce(p_position_ms, 0)),
        v_user,
        now(),
        normalized_command,
        p_latency_ms
    )
    on conflict (session_id) do update
        set media_type = excluded.media_type,
            media_id = excluded.media_id,
            media_url = excluded.media_url,
            media_title = excluded.media_title,
            media_thumbnail = excluded.media_thumbnail,
            duration_ms = excluded.duration_ms,
            state = excluded.state,
            position_ms = excluded.position_ms,
            initiated_by = excluded.initiated_by,
            updated_at = now(),
            last_command = excluded.last_command,
            latency_ms = excluded.latency_ms
    returning * into v_row;

    insert into public.call_shared_media_events (
        session_id,
        thread_id,
        user_id,
        media_id,
        command,
        state,
        position_ms,
        latency_ms,
        payload
    ) values (
        p_session_id,
        p_thread_id,
        v_user,
        p_media_id,
        normalized_command,
        normalized_state,
        greatest(0, coalesce(p_position_ms, 0)),
        p_latency_ms,
        jsonb_build_object(
            'mediaTitle', p_media_title,
            'mediaUrl', p_media_url,
            'thumbnail', p_media_thumbnail,
            'durationMs', p_duration_ms
        )
    );

    return v_row;
end;
$$;

drop function if exists public.call_shared_media_get_state(uuid);
create or replace function public.call_shared_media_get_state(p_thread_id uuid)
returns public.call_shared_media_state
language sql
security definer
set search_path = public
as $$
    select s.*
      from public.call_shared_media_state s
     where s.thread_id = p_thread_id
     order by s.updated_at desc
     limit 1;
$$;

drop function if exists public.call_shared_media_list(text);
create or replace function public.call_shared_media_list(p_media_type text default null)
returns table (
    id text,
    media_type text,
    title text,
    description text,
    media_url text,
    thumbnail_url text,
    duration_ms integer,
    source text
)
language sql
security definer
set search_path = public
as $$
    select c.id,
           c.media_type,
           c.title,
           c.description,
           c.media_url,
           c.thumbnail_url,
           c.duration_ms,
           c.source
      from public.call_shared_media_catalog c
     where c.is_active
       and (p_media_type is null or c.media_type = lower(p_media_type))
     order by c.media_type, c.title;
$$;

insert into public.call_shared_media_catalog (id, media_type, title, description, media_url, thumbnail_url, duration_ms, source)
values
    ('lofi-chill', 'music', 'Lo-Fi Chill', 'Relaxed hip-hop instrumental', 'https://samplelib.com/lib/preview/mp3/sample-3s.mp3', 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&w=400&q=80', 180000, 'samplelib'),
    ('ambient-rain', 'music', 'Ambient Rain', 'Calming rain ambience', 'https://samplelib.com/lib/preview/mp3/sample-6s.mp3', 'https://images.unsplash.com/photo-1504384308090-c894fdcc538d?auto=format&fit=crop&w=400&q=80', 240000, 'samplelib'),
    ('nature-travel', 'video', 'Nature Travel Clip', 'Slow travel through nature scenes', 'https://samplelib.com/lib/preview/mp4/sample-5s.mp4', 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=400&q=80', 300000, 'samplelib'),
    ('city-timelapse', 'video', 'City Timelapse', 'Night timelapse skyline', 'https://samplelib.com/lib/preview/mp4/sample-10s.mp4', 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=400&q=80', 150000, 'samplelib')
on conflict (id) do update
    set title = excluded.title,
        description = excluded.description,
        media_url = excluded.media_url,
        thumbnail_url = excluded.thumbnail_url,
        duration_ms = excluded.duration_ms,
        source = excluded.source,
        is_active = true;

-- ---------------------------------------------------------------------------
-- Scheduled maintenance helpers
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------

create table if not exists public.chat_push_tokens (
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    platform text not null check (platform in ('android', 'ios', 'web')),
    provider text not null default 'fcm',
    device_id text,
    app_version text,
    language text,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_seen_at timestamptz,
    primary key (user_id, token)
);

create index if not exists idx_chat_push_tokens_token on public.chat_push_tokens(token);
create index if not exists idx_chat_push_tokens_user on public.chat_push_tokens(user_id);

create table if not exists public.chat_notification_logs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null,
    event_type text not null,
    thread_id uuid,
    reference_id uuid,
    payload jsonb,
    success boolean not null default true,
    error text,
    created_at timestamptz not null default now()
);

create index if not exists idx_chat_notification_logs_user_time
  on public.chat_notification_logs(user_id, created_at desc);

create index if not exists idx_chat_notification_logs_thread
  on public.chat_notification_logs(thread_id);

create table if not exists public.chat_notify_outbox (
    id uuid primary key default gen_random_uuid(),
    event_type text not null default 'message' check (event_type in ('message','reaction','guest','system')),
    thread_id uuid not null references public.chat_threads(id) on delete cascade,
    message_id uuid references public.chat_messages(id) on delete cascade,
    sender_id uuid references auth.users(id) on delete cascade,
    title text,
    body text,
    payload jsonb not null default '{}'::jsonb,
    status text not null default 'pending' check (status in ('pending','processing','queued','sent','failed')),
    attempts integer not null default 0,
    last_error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index if not exists idx_chat_notify_outbox_message
  on public.chat_notify_outbox(event_type, message_id)
  where message_id is not null;

create index if not exists idx_chat_notify_outbox_status_created
  on public.chat_notify_outbox(status, created_at);

create or replace function public.chat_touch_notify_outbox()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists chat_touch_notify_outbox_bu on public.chat_notify_outbox;

create trigger chat_touch_notify_outbox_bu
before update on public.chat_notify_outbox
for each row
execute function public.chat_touch_notify_outbox();

create table if not exists public.chat_stories (
    id uuid primary key default gen_random_uuid(),
    author_id uuid not null references auth.users(id) on delete cascade,
    media_url text not null,
    media_thumb_url text,
    caption text,
    visibility text not null default 'friends' check (visibility in ('friends','public','private')),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    deleted_at timestamptz
);

create index if not exists idx_chat_stories_author_time
  on public.chat_stories(author_id, created_at desc);

create index if not exists idx_chat_stories_expires_at
  on public.chat_stories(expires_at);

create table if not exists public.chat_story_views (
    story_id uuid not null references public.chat_stories(id) on delete cascade,
    viewer_id uuid not null references auth.users(id) on delete cascade,
    viewed_at timestamptz not null default now(),
    primary key (story_id, viewer_id)
);

create table if not exists public.chat_story_reactions (
    story_id uuid not null references public.chat_stories(id) on delete cascade,
    reactor_id uuid not null references auth.users(id) on delete cascade,
    reaction text not null,
    created_at timestamptz not null default now(),
    primary key (story_id, reactor_id)
);

alter table public.chat_stories enable row level security;
alter table public.chat_story_views enable row level security;
alter table public.chat_story_reactions enable row level security;

drop policy if exists "Stories viewable" on public.chat_stories;
create policy "Stories viewable"
    on public.chat_stories
    for select using (
        visibility in ('public','friends')
        or author_id = auth.uid()
    );

drop policy if exists "Stories self manage" on public.chat_stories;
create policy "Stories self manage"
    on public.chat_stories
    for all
    using (author_id = auth.uid())
    with check (author_id = auth.uid());

drop policy if exists "View own story stats" on public.chat_story_views;
create policy "View own story stats"
    on public.chat_story_views
    for select using (
        viewer_id = auth.uid()
        or exists (
            select 1
              from public.chat_stories s
             where s.id = story_id
               and s.author_id = auth.uid()
        )
    );

drop policy if exists "Record story views" on public.chat_story_views;
create policy "Record story views"
    on public.chat_story_views
    for insert
    with check (viewer_id = auth.uid());

drop policy if exists "React to stories" on public.chat_story_reactions;
create policy "React to stories"
    on public.chat_story_reactions
    for insert
    with check (reactor_id = auth.uid());

drop policy if exists "View story reactions" on public.chat_story_reactions;
create policy "View story reactions"
    on public.chat_story_reactions
    for select using (
        reactor_id = auth.uid()
        or exists (
            select 1
              from public.chat_stories s
             where s.id = story_id
               and s.author_id = auth.uid()
        )
    );

create or replace function public.chat_touch_push_token()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at := now();
    if new.last_seen_at is null then
        new.last_seen_at := new.updated_at;
    end if;
    return new;
end;
$$;

drop trigger if exists chat_touch_push_token_bu on public.chat_push_tokens;

create trigger chat_touch_push_token_bu
before update on public.chat_push_tokens
for each row
execute function public.chat_touch_push_token();

alter table public.chat_push_tokens enable row level security;

drop policy if exists "Own push tokens" on public.chat_push_tokens;

create policy "Own push tokens"
    on public.chat_push_tokens
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

grant insert, update, delete, select on public.chat_push_tokens to authenticated;
grant insert, update, delete, select on public.chat_push_tokens to anon;

grant select on public.chat_notification_logs to service_role;
grant insert on public.chat_notification_logs to service_role;
grant select, insert, update on public.chat_notify_outbox to service_role;
grant select, insert, update, delete on public.chat_stories to service_role;
grant select, insert, update, delete on public.chat_story_views to service_role;
grant select, insert, update, delete on public.chat_story_reactions to service_role;
grant select, insert, update, delete on public.chat_stories to authenticated;
grant select, insert, update, delete on public.chat_story_views to authenticated;
grant select, insert, update, delete on public.chat_story_reactions to authenticated;

create or replace function public.chat_register_push_token(
    p_token text,
    p_platform text,
    p_device_id text default null,
    p_app_version text default null,
    p_language text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user uuid := auth.uid();
    normalized_platform text := lower(trim(p_platform));
begin
    if current_user is null then
        raise exception 'Not authenticated';
    end if;
    if coalesce(trim(p_token), '') = '' then
        raise exception 'Push token required';
    end if;
    if normalized_platform not in ('android', 'ios', 'web') then
        raise exception 'Unsupported platform %', normalized_platform;
    end if;

    insert into public.chat_push_tokens (user_id, token, platform, provider, device_id, app_version, language, is_active, last_seen_at)
    values (
        current_user,
        trim(p_token),
        normalized_platform,
        'fcm',
        nullif(trim(p_device_id), ''),
        nullif(trim(p_app_version), ''),
        nullif(trim(p_language), ''),
        true,
        now()
    )
    on conflict (user_id, token) do update
        set platform = excluded.platform,
            provider = excluded.provider,
            device_id = excluded.device_id,
            app_version = excluded.app_version,
            language = excluded.language,
            is_active = true,
            last_seen_at = now();
end;
$$;

create or replace function public.chat_unregister_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user uuid := auth.uid();
begin
    if current_user is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.chat_push_tokens
     where user_id = current_user
       and token = trim(p_token);
end;
$$;

create or replace function public.chat_log_notifications(p_logs jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.chat_notification_logs (
        user_id,
        token,
        event_type,
        thread_id,
        reference_id,
        payload,
        success,
        error,
        created_at
    )
    select (entry->>'user_id')::uuid,
           entry->>'token',
           entry->>'event_type',
           nullif(entry->>'thread_id', '')::uuid,
           nullif(entry->>'reference_id', '')::uuid,
           entry->'payload',
           coalesce((entry->>'success')::boolean, false),
           entry->>'error',
           coalesce(nullif(entry->>'created_at', '')::timestamptz, now())
      from jsonb_array_elements(p_logs) as entry;
end;
$$;

create or replace function public.chat_request_notification(
    p_event_type text,
    p_thread_id uuid,
    p_actor_id uuid default null,
    p_reference_id uuid default null,
    p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    event text := lower(trim(coalesce(p_event_type, '')));
    worker_url text := coalesce(
        nullif(current_setting('app.settings.chat_notify_worker_url', true), ''),
        current_setting('app.settings.chat_notify_url', true)
    );
    worker_auth text := current_setting('app.settings.chat_notify_worker_auth', true);
    thread_title text := null;
    actor_name text := null;
    message_rec record;
    message_preview text;
    payload jsonb := jsonb_build_object(
        'eventType', event,
        'threadId', p_thread_id,
        'actorId', p_actor_id,
        'referenceId', p_reference_id,
        'metadata', coalesce(p_metadata, '{}'::jsonb)
    );
    headers jsonb := jsonb_build_object('Content-Type', 'application/json');
begin
    if coalesce(worker_auth, '') <> '' then
        headers := headers || jsonb_build_object('Authorization', worker_auth);
    end if;

    if event = 'message' then
        select coalesce(nullif(t.title, ''), 'New message')
          into thread_title
          from public.chat_threads t
         where t.id = p_thread_id;

        select coalesce(pp.username, 'Someone')
          into actor_name
          from public.public_profiles pp
         where pp.id = p_actor_id;

        select m.body, m.message_type
          into message_rec
          from public.chat_messages m
         where m.id = p_reference_id
           and m.deleted_at is null;

        if message_rec.message_type is null then
            message_rec.message_type := 'text';
        end if;

        message_preview := coalesce(
            nullif(message_rec.body, ''),
            case message_rec.message_type
                when 'image' then 'Sent a photo'
                when 'video' then 'Sent a video'
                when 'file' then 'Shared a file'
                else 'Sent a message'
            end
        );

        insert into public.chat_notify_outbox (
            event_type,
            thread_id,
            message_id,
            sender_id,
            title,
            body,
            payload,
            status,
            last_error
        )
        values (
            event,
            p_thread_id,
            p_reference_id,
            p_actor_id,
            coalesce(thread_title, 'New message'),
            left(coalesce(actor_name, 'Someone') || ': ' || coalesce(message_preview, 'New message'), 180),
            payload,
            'pending',
            null
        )
        on conflict (event_type, message_id) do update
            set title = excluded.title,
                body = excluded.body,
                payload = excluded.payload,
                status = 'pending',
                last_error = null,
                updated_at = now();

        if coalesce(worker_url, '') = '' then
            return;
        end if;

        begin
            perform net.http_post(
                url := worker_url,
                headers := headers,
                body := jsonb_build_object(
                    'trigger', 'chat_notify',
                    'threadId', p_thread_id,
                    'messageId', p_reference_id
                )::text
            );

            update public.chat_notify_outbox
               set status = 'queued',
                   attempts = attempts + 1
             where event_type = event
               and message_id = p_reference_id;
        exception when others then
            update public.chat_notify_outbox
               set status = 'failed',
                   attempts = attempts + 1,
                   last_error = left(sqlerrm, 400)
             where event_type = event
               and message_id = p_reference_id;
        end;
        return;
    end if;

    if coalesce(worker_url, '') = '' then
        return;
    end if;

    perform net.http_post(
        url := worker_url,
        headers := headers,
        body := payload::text
    );
end;
$$;

create or replace function public.chat_collect_notification_targets(
    p_event_type text,
    p_thread_id uuid,
    p_actor_id uuid,
    p_reference_id uuid,
    p_metadata jsonb default '{}'::jsonb
) returns table (
    user_id uuid,
    token text,
    platform text,
    title text,
    body text,
    data jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
    event text := lower(trim(p_event_type));
    thread_rec record;
    actor_profile record;
    message_rec record;
    actor_name text;
    thread_title text;
    base_title text;
    base_body text;
    max_per_minute integer := 12;
    message_preview text;
    data_payload jsonb := '{}'::jsonb;
    reaction_text text := coalesce(p_metadata->>'reaction', '');
    guest_id uuid := nullif(p_metadata->>'guest_id', '')::uuid;
begin
    select t.id,
           t.is_group,
           coalesce(nullif(t.title, ''), nullif(owner_profile.username, '')) as computed_title
      into thread_rec
      from public.chat_threads t
      left join public.chat_thread_participants owner_part on owner_part.thread_id = t.id and owner_part.user_id = p_actor_id
      left join public.public_profiles owner_profile on owner_profile.id = owner_part.user_id
     where t.id = p_thread_id;

    if thread_rec.id is null then
        return;
    end if;

    select prof.username, prof.avatar_url
      into actor_profile
      from public.public_profiles prof
     where prof.id = p_actor_id;

    actor_name := coalesce(actor_profile.username, 'Someone');
    thread_title := coalesce(thread_rec.computed_title, actor_name, 'New message');

    if event = 'message' then
        select m.id,
               m.body,
               m.message_type,
               m.created_at
          into message_rec
          from public.chat_messages m
         where m.id = p_reference_id
           and m.deleted_at is null;

        if message_rec.id is null then
            return;
        end if;

        message_preview := coalesce(nullif(message_rec.body, ''), case message_rec.message_type
            when 'image' then 'Sent a photo'
            when 'video' then 'Sent a video'
            when 'file' then 'Shared a file'
            else 'Sent a message'
        end);

        base_title := thread_title;
        base_body := actor_name || ': ' || message_preview;
        data_payload := jsonb_build_object(
            'type', 'message',
            'threadId', p_thread_id,
            'messageId', message_rec.id,
            'senderId', p_actor_id,
            'messageType', message_rec.message_type
        );
    elsif event = 'reaction' then
        base_title := thread_title;
        base_body := actor_name || ' reacted' || case when reaction_text <> '' then ' with ' || reaction_text else '' end;
        data_payload := jsonb_build_object(
            'type', 'reaction',
            'threadId', p_thread_id,
            'messageId', p_reference_id,
            'actorId', p_actor_id,
            'reaction', reaction_text
        );
    elsif event = 'guest_expired' then
        base_title := thread_title;
        base_body := 'Guest access expired';
        if guest_id is not null then
            select coalesce(username, 'The guest')
              into actor_name
              from public.public_profiles
             where id = guest_id;
            base_body := actor_name || ' no longer has access to this chat';
        end if;
        data_payload := jsonb_build_object(
            'type', 'guest_expired',
            'threadId', p_thread_id,
            'guestId', guest_id,
            'actorId', p_actor_id
        );
    else
        return;
    end if;

    return query
    with participant_scope as (
        select tp.user_id,
               tp.role,
               tp.muted_until,
               tp.thread_id
          from public.chat_thread_participants tp
         where tp.thread_id = p_thread_id
           and (tp.user_id <> p_actor_id or p_actor_id is null)
    ),
    permitted_recipients as (
        select ps.user_id
          from participant_scope ps
          left join public.chat_guest_access ga
            on ga.thread_id = ps.thread_id
           and ga.guest_id = ps.user_id
          left join public.chat_notification_logs recent
            on recent.user_id = ps.user_id
           and recent.created_at >= now() - interval '1 minute'
         where coalesce(ps.muted_until, timestamp 'epoch') <= now()
           and (
                ps.role <> 'guest'
                or (ga.revoked_at is null and ga.expires_at > now())
           )
         group by ps.user_id
        having count(recent.id) < max_per_minute
    )
    select pt.user_id,
           pt.token,
           pt.platform,
           base_title,
           base_body,
           data_payload
      from permitted_recipients pr
      join public.chat_push_tokens pt
        on pt.user_id = pr.user_id
       and pt.is_active = true
       and coalesce(pt.updated_at, now()) >= now() - interval '180 days';
end;
$$;

create or replace function public.chat_expire_guest_access()
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_ts timestamptz := now();
    revoked_count integer := 0;
    removed_count integer := 0;
    touched_threads uuid[] := array[]::uuid[];
    rec record;
    removed_threads uuid[] := array[]::uuid[];
begin
    for rec in
        update public.chat_guest_access ga
           set revoked_at = current_ts
         where ga.revoked_at is null
           and ga.expires_at <= current_ts
         returning ga.thread_id, ga.guest_id
    loop
        revoked_count := revoked_count + 1;
        touched_threads := touched_threads || rec.thread_id;
        perform public.chat_request_notification(
            p_event_type => 'guest_expired',
            p_thread_id => rec.thread_id,
            p_actor_id => rec.guest_id,
            p_reference_id => null,
            p_metadata => jsonb_build_object('guest_id', rec.guest_id)
        );
    end loop;

    with removed as (
        delete from public.chat_thread_participants tp
         where tp.role = 'guest'
           and not exists (
                select 1
                  from public.chat_guest_access ga
                 where ga.thread_id = tp.thread_id
                   and ga.guest_id = tp.user_id
                   and ga.revoked_at is null
                   and ga.expires_at > current_ts
            )
         returning tp.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into removed_count, removed_threads
      from removed;

    touched_threads := touched_threads || removed_threads;
    touched_threads := array(SELECT DISTINCT unnest(touched_threads));

    if array_length(touched_threads, 1) is not null then
        update public.chat_threads t
           set updated_at = current_ts
         where t.id = any(touched_threads);
    end if;

    return jsonb_build_object(
        'revoked_guest_access', revoked_count,
        'guests_removed', removed_count
    );
end;
$$;

create or replace function public.chat_prune_temp_invites(p_pending_grace_minutes integer default 1440)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_ts timestamptz := now();
    cutoff timestamptz := current_ts - make_interval(mins => greatest(p_pending_grace_minutes, 1));
    expired_count integer := 0;
    cancelled_count integer := 0;
    deleted_count integer := 0;
begin
    with expired as (
        update public.chat_temp_guest_invites inv
           set status = 'expired',
               responded_at = coalesce(inv.responded_at, current_ts)
         where inv.status = 'pending'
           and inv.expires_at is not null
           and inv.expires_at <= current_ts
         returning inv.thread_id
    ),
    cancelled as (
        update public.chat_temp_guest_invites inv
           set status = 'cancelled',
               responded_at = coalesce(inv.responded_at, current_ts),
               expires_at = null
         where inv.status = 'pending'
           and inv.expires_at is null
           and inv.created_at <= cutoff
         returning inv.thread_id
    ),
    deleted as (
        delete from public.chat_temp_guest_invites inv
         where inv.status in ('cancelled', 'declined', 'expired')
           and inv.responded_at is not null
           and inv.responded_at <= current_ts - interval '30 days'
         returning inv.thread_id
    ),
    touch as (
        update public.chat_threads t
           set updated_at = current_ts
         where t.id in (
                select thread_id from expired
                union
                select thread_id from cancelled
         )
         returning 1
    )
    select coalesce((select count(*) from expired), 0),
           coalesce((select count(*) from cancelled), 0),
           coalesce((select count(*) from deleted), 0)
      into expired_count, cancelled_count, deleted_count;

    return jsonb_build_object(
        'expired_invites', expired_count,
        'auto_cancelled', cancelled_count,
        'deleted_old', deleted_count
    );
end;
$$;

create or replace function public.chat_cleanup_empty_threads()
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_ts timestamptz := now();
    deleted_threads integer := 0;
begin
    with orphan_threads as (
        select t.id
          from public.chat_threads t
         where not exists (
                   select 1
                     from public.chat_thread_participants tp
                    where tp.thread_id = t.id
               )
            or (
                 not exists (
                       select 1
                         from public.chat_thread_participants tp
                        where tp.thread_id = t.id
                          and tp.role <> 'guest'
                    )
                 and not exists (
                       select 1
                         from public.chat_guest_access ga
                        where ga.thread_id = t.id
                          and ga.revoked_at is null
                          and ga.expires_at > current_ts
                    )
               )
    ),
    removed_threads as (
        delete from public.chat_threads t
         where t.id in (select id from orphan_threads)
         returning t.id
    )
    select coalesce((select count(*) from removed_threads), 0)
      into deleted_threads;

    return jsonb_build_object(
        'threads_deleted', deleted_threads
    );
end;
$$;

create or replace function public.chat_remove_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    reactions_removed integer := 0;
    guest_access_removed integer := 0;
    temp_invites_removed integer := 0;
    group_invites_removed integer := 0;
    messages_removed integer := 0;
    participants_removed integer := 0;
    threads_detached integer := 0;
    push_tokens_removed integer := 0;
    cleanup_result jsonb := '{}'::jsonb;
    touched_threads uuid[] := array[]::uuid[];
    ids uuid[] := array[]::uuid[];
begin
    if p_user_id is null then
        raise exception 'User id required';
    end if;

    with removed as (
        delete from public.chat_message_reactions cmr
         where cmr.user_id = p_user_id
         returning 1
    )
    select coalesce(count(*), 0)
      into reactions_removed
      from removed;

    with removed_ga as (
        delete from public.chat_guest_access ga
         where ga.guest_id = p_user_id
         returning ga.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into guest_access_removed, ids
      from removed_ga;
    touched_threads := touched_threads || ids;

    with removed_inv as (
        delete from public.chat_temp_guest_invites inv
         where inv.guest_id = p_user_id
            or inv.requested_by = p_user_id
         returning inv.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into temp_invites_removed, ids
      from removed_inv;
    touched_threads := touched_threads || ids;

    with removed_group as (
        delete from public.chat_group_invitations gi
         where gi.invited_user_id = p_user_id
            or gi.invited_by = p_user_id
         returning gi.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into group_invites_removed, ids
      from removed_group;
    touched_threads := touched_threads || ids;

    with updated_threads as (
        update public.chat_threads t
           set created_by = null
         where t.created_by = p_user_id
         returning t.id
    )
    select coalesce(count(*), 0), coalesce(array_agg(id), array[]::uuid[])
      into threads_detached, ids
      from updated_threads;
    touched_threads := touched_threads || ids;

    with removed_messages as (
        delete from public.chat_messages m
         where m.sender_id = p_user_id
         returning m.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into messages_removed, ids
      from removed_messages;
    touched_threads := touched_threads || ids;

    with removed_participants as (
        delete from public.chat_thread_participants tp
         where tp.user_id = p_user_id
         returning tp.thread_id
    )
    select coalesce(count(*), 0), coalesce(array_agg(thread_id), array[]::uuid[])
      into participants_removed, ids
      from removed_participants;
    touched_threads := touched_threads || ids;

    with removed_tokens as (
        delete from public.chat_push_tokens pt
         where pt.user_id = p_user_id
         returning 1
    )
    select coalesce(count(*), 0)
      into push_tokens_removed
      from removed_tokens;

    touched_threads := array_remove(touched_threads, null);

    if array_length(touched_threads, 1) is not null then
        update public.chat_threads t
           set updated_at = now()
         where t.id = any(touched_threads);
    end if;

    cleanup_result := public.chat_cleanup_empty_threads();

    return jsonb_build_object(
        'reactions_removed', reactions_removed,
        'guest_access_removed', guest_access_removed,
        'temp_invites_removed', temp_invites_removed,
        'group_invites_removed', group_invites_removed,
        'messages_removed', messages_removed,
        'participants_removed', participants_removed,
        'threads_detached', threads_detached,
        'push_tokens_removed', push_tokens_removed,
        'cleanup', cleanup_result
    );
end;
$$;

create or replace function public.chat_sweep_orphan_users(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    effective_limit integer := greatest(coalesce(p_limit, 50), 1);
    orphan_ids uuid[];
    processed integer := 0;
    details jsonb := '[]'::jsonb;
    failures jsonb := '[]'::jsonb;
    orphan_id uuid;
    result jsonb;
begin
    select array_agg(id)
      into orphan_ids
      from (
        select distinct candidate_id as id
          from (
            select tp.user_id as candidate_id
              from public.chat_thread_participants tp
              left join auth.users u on u.id = tp.user_id
             where u.id is null
            union all
            select m.sender_id as candidate_id
              from public.chat_messages m
              left join auth.users u on u.id = m.sender_id
             where u.id is null
            union all
            select ga.guest_id as candidate_id
              from public.chat_guest_access ga
              left join auth.users u on u.id = ga.guest_id
             where u.id is null
            union all
            select inv.guest_id as candidate_id
              from public.chat_temp_guest_invites inv
              left join auth.users u on u.id = inv.guest_id
             where u.id is null
            union all
            select inv.requested_by as candidate_id
              from public.chat_temp_guest_invites inv
              left join auth.users u on u.id = inv.requested_by
             where inv.requested_by is not null
               and u.id is null
            union all
            select gi.invited_user_id as candidate_id
              from public.chat_group_invitations gi
              left join auth.users u on u.id = gi.invited_user_id
             where u.id is null
            union all
            select gi.invited_by as candidate_id
              from public.chat_group_invitations gi
              left join auth.users u on u.id = gi.invited_by
             where gi.invited_by is not null
               and u.id is null
            union all
            select t.created_by as candidate_id
              from public.chat_threads t
              left join auth.users u on u.id = t.created_by
             where t.created_by is not null
               and u.id is null
            union all
            select pt.user_id as candidate_id
              from public.chat_push_tokens pt
              left join auth.users u on u.id = pt.user_id
             where u.id is null
            union all
            select cmr.user_id as candidate_id
              from public.chat_message_reactions cmr
              left join auth.users u on u.id = cmr.user_id
             where u.id is null
          ) candidates
         where candidate_id is not null
         order by candidate_id
         limit effective_limit
      ) limited;

    if orphan_ids is null or array_length(orphan_ids, 1) is null then
        return jsonb_build_object(
            'found', 0,
            'processed', 0,
            'failed', 0,
            'details', '[]'::jsonb,
            'failures', '[]'::jsonb
        );
    end if;

    foreach orphan_id in array orphan_ids loop
        begin
            result := public.chat_remove_user(orphan_id);
            details := details || jsonb_build_array(jsonb_build_object(
                'user_id', orphan_id,
                'result', result
            ));
            processed := processed + 1;
        exception when others then
            failures := failures || jsonb_build_array(jsonb_build_object(
                'user_id', orphan_id,
                'error', SQLERRM
            ));
        end;
    end loop;

    return jsonb_build_object(
        'found', array_length(orphan_ids, 1),
        'processed', processed,
        'failed', jsonb_array_length(failures),
        'details', details,
        'failures', failures
    );
end;
$$;

create or replace function public.chat_list_threads()
returns setof jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    thread_id uuid;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    for thread_id in
        select t.id
          from public.chat_threads t
          join public.chat_thread_participants tp on tp.thread_id = t.id
         where tp.user_id = current_user_id
         order by t.updated_at desc
    loop
        return next public.chat_thread_summary(thread_id, current_user_id);
    end loop;

    return;
end;
$$;

create or replace function public.chat_start_thread(p_recipient_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    existing_thread uuid;
    new_thread uuid;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_recipient_id is null then
        raise exception 'Recipient required';
    end if;
    if p_recipient_id = current_user_id then
        raise exception 'Cannot start a chat with yourself';
    end if;

    select t.id into existing_thread
      from public.chat_threads t
      join public.chat_thread_participants a on a.thread_id = t.id and a.user_id = current_user_id
      join public.chat_thread_participants b on b.thread_id = t.id and b.user_id = p_recipient_id
     limit 1;

    if existing_thread is null then
        insert into public.chat_threads (is_group, created_by)
        values (false, current_user_id)
        returning id into new_thread;
        perform public.chat_upsert_participant(new_thread, current_user_id);
        perform public.chat_upsert_participant(new_thread, p_recipient_id);
        existing_thread := new_thread;
    end if;

    return public.chat_thread_summary(existing_thread, current_user_id);
end;
$$;

create or replace function public.chat_edit_message(
    p_message_id uuid,
    p_body text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    existing chat_messages;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_message_id is null then
        raise exception 'Message id required';
    end if;

    select *
      into existing
      from public.chat_messages
     where id = p_message_id
       and deleted_at is null;

    if existing.id is null then
        raise exception 'Message not found';
    end if;
    if existing.sender_id <> current_user_id then
        raise exception 'You can only edit your own messages';
    end if;

    update public.chat_messages
       set body = p_body,
           edited_at = now()
     where id = p_message_id;

    return (select row_to_json(m)
              from public.chat_messages m
             where m.id = p_message_id);
end;
$$;

create or replace function public.chat_delete_message(
    p_message_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    existing chat_messages;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_message_id is null then
        raise exception 'Message id required';
    end if;

    select *
      into existing
      from public.chat_messages
     where id = p_message_id;

    if existing.id is null then
        raise exception 'Message not found';
    end if;
    if existing.sender_id <> current_user_id then
        raise exception 'You can only delete your own messages';
    end if;

    update public.chat_messages
       set body = null,
           attachment_url = null,
           attachment_thumb_url = null,
           attachment_metadata = null,
           edited_at = now(),
           deleted_at = now(),
           deleted_by = current_user_id
     where id = p_message_id;

    delete from public.chat_message_reactions cmr
     where cmr.message_id = p_message_id;

    return (select row_to_json(m)
              from public.chat_messages m
             where m.id = p_message_id);
end;
$$;

create or replace function public.chat_mark_thread_read(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
begin
    if current_user_id is null then
        return;
    end if;

    update public.chat_thread_participants
       set last_read_at = greatest(coalesce(last_read_at, '1970-01-01'::timestamptz), now())
     where thread_id = p_thread_id
       and user_id = current_user_id;
end;
$$;

drop function if exists public.chat_set_thread_mute(uuid, timestamptz);

create or replace function public.chat_set_thread_mute(
    p_thread_id uuid,
    p_muted_until timestamptz default null
) returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_user_id uuid := auth.uid();
    sanitized_until timestamptz := p_muted_until;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_thread_id is null then
        raise exception 'Thread id required';
    end if;

    if sanitized_until is not null and sanitized_until <= now() then
        sanitized_until := null;
    end if;

    update public.chat_thread_participants
       set muted_until = sanitized_until
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if not found then
        raise exception 'You are not a participant of this thread';
    end if;
end;
$$;

create or replace function public.chat_create_group(
    p_title text,
    p_member_ids uuid[],
    p_avatar_url text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    new_thread uuid;
    member_id uuid;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if array_length(p_member_ids, 1) is null then
        raise exception 'At least one participant required';
    end if;

    insert into public.chat_threads (is_group, title, avatar_url, created_by)
    values (true, trim(nullif(p_title, '')), p_avatar_url, current_user_id)
    returning id into new_thread;

    perform public.chat_upsert_participant(new_thread, current_user_id, 'owner', current_user_id);

    foreach member_id in array p_member_ids loop
        exit when member_id is null;
        if member_id <> current_user_id then
            perform public.chat_upsert_participant(new_thread, member_id, 'member', current_user_id);
        end if;
    end loop;

    return public.chat_thread_summary(new_thread, current_user_id);
end;
$$;

create or replace function public.chat_add_participants(
    p_thread_id uuid,
    p_member_ids uuid[]
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    member_id uuid;
    current_role text;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    select role into current_role
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if current_role not in ('owner', 'admin') then
        raise exception 'You do not have permission to add participants';
    end if;

    foreach member_id in array p_member_ids loop
        exit when member_id is null;
        if not exists (
            select 1 from public.chat_thread_participants
            where thread_id = p_thread_id and user_id = member_id
        ) then
            perform public.chat_upsert_participant(p_thread_id, member_id, 'member', current_user_id);
        end if;
    end loop;

    update public.chat_threads
       set updated_at = now()
     where id = p_thread_id;

    return public.chat_thread_summary(p_thread_id, current_user_id);
end;
$$;

create or replace function public.chat_remove_participant(
    p_thread_id uuid,
    p_member_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    current_role text;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    if p_member_id = current_user_id then
        perform public.chat_leave_group(p_thread_id);
        return;
    end if;

    select role into current_role
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if current_role not in ('owner', 'admin') then
        raise exception 'You do not have permission to remove participants';
    end if;

    delete from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = p_member_id;

    update public.chat_threads
       set updated_at = now()
     where id = p_thread_id;
end;
$$;

create or replace function public.chat_leave_group(
    p_thread_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    member_count integer;
    current_role text;
    owner_id uuid;
    new_owner uuid;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    select role into current_role
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if current_role is null then
        raise exception 'You are not a participant of this group';
    end if;

    delete from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    select count(*) into member_count
      from public.chat_thread_participants
     where thread_id = p_thread_id;

    if member_count = 0 then
        delete from public.chat_threads where id = p_thread_id;
        return;
    end if;

    select user_id into owner_id
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and role = 'owner'
     limit 1;

    if owner_id is null then
        select user_id into new_owner
          from public.chat_thread_participants
         where thread_id = p_thread_id
         order by joined_at
         limit 1;

        update public.chat_thread_participants
           set role = 'owner'
         where thread_id = p_thread_id
           and user_id = new_owner;
    end if;

    update public.chat_threads
       set updated_at = now()
     where id = p_thread_id;
end;
$$;

create or replace function public.chat_update_group(
    p_thread_id uuid,
    p_title text,
    p_avatar_url text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    current_role text;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    select role into current_role
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if current_role not in ('owner', 'admin') then
        raise exception 'You do not have permission to update this group';
    end if;

    update public.chat_threads
       set title = trim(nullif(p_title, '')),
           avatar_url = p_avatar_url,
           updated_at = now()
     where id = p_thread_id;

    return public.chat_thread_summary(p_thread_id, current_user_id);
end;
$$;

drop function if exists public.chat_request_temp_guest(uuid, uuid, integer);

create or replace function public.chat_request_temp_guest(
    p_thread_id uuid,
    p_guest_id uuid,
    p_duration_minutes integer
) returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_user_id uuid := auth.uid();
    sanitized_duration integer;
    invite_rec public.chat_temp_guest_invites%rowtype;
    requester_role text;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_thread_id is null then
        raise exception 'Thread id required';
    end if;
    if p_guest_id is null then
        raise exception 'Guest id required';
    end if;
    if p_guest_id = current_user_id then
        raise exception 'Cannot invite yourself';
    end if;

    sanitized_duration := greatest(10, least(coalesce(p_duration_minutes, 30), 1440));

    select role into requester_role
      from public.chat_thread_participants
     where thread_id = p_thread_id
       and user_id = current_user_id;

    if requester_role is null then
        raise exception 'You do not belong to this thread';
    end if;

    if requester_role not in ('owner', 'admin') then
        raise exception 'You do not have permission to invite guests';
    end if;

    if exists (
        select 1
          from public.chat_thread_participants tp
         where tp.thread_id = p_thread_id
           and tp.user_id = p_guest_id
    ) then
        raise exception 'User is already part of this thread';
    end if;

    delete from public.chat_temp_guest_invites
     where thread_id = p_thread_id
       and guest_id = p_guest_id
       and status = 'pending';

    insert into public.chat_temp_guest_invites (
        thread_id,
        guest_id,
        requested_by,
        duration_minutes,
        status,
        created_at,
        responded_at,
        expires_at
    ) values (
        p_thread_id,
        p_guest_id,
        current_user_id,
        sanitized_duration,
        'pending',
        now(),
        null,
        null
    )
    returning * into invite_rec;

    update public.chat_threads
       set updated_at = now()
     where id = p_thread_id;

    return jsonb_build_object(
        'invite_id', invite_rec.id,
        'thread_id', invite_rec.thread_id,
        'guest_id', invite_rec.guest_id,
        'requested_by', invite_rec.requested_by,
        'duration_minutes', invite_rec.duration_minutes,
        'created_at', invite_rec.created_at
    );
end;
$$;

drop function if exists public.chat_cancel_temp_guest(uuid);

create or replace function public.chat_cancel_temp_guest(
    p_invite_id uuid
) returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_user_id uuid := auth.uid();
    invite_rec public.chat_temp_guest_invites%rowtype;
    requester_role text;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    select *
      into invite_rec
      from public.chat_temp_guest_invites
     where id = p_invite_id;

    if invite_rec is null then
        raise exception 'Invite not found';
    end if;

    select role into requester_role
      from public.chat_thread_participants
     where thread_id = invite_rec.thread_id
       and user_id = current_user_id;

    if current_user_id <> invite_rec.requested_by
       and (requester_role is null or requester_role not in ('owner', 'admin')) then
        raise exception 'You do not have permission to cancel this invite';
    end if;

    update public.chat_temp_guest_invites
       set status = 'cancelled',
           responded_at = now(),
           expires_at = null
     where id = p_invite_id;

    update public.chat_guest_access
       set revoked_at = now()
     where thread_id = invite_rec.thread_id
       and guest_id = invite_rec.guest_id
       and revoked_at is null;

    delete from public.chat_thread_participants
     where thread_id = invite_rec.thread_id
       and user_id = invite_rec.guest_id
       and role = 'guest';

    update public.chat_threads
       set updated_at = now()
     where id = invite_rec.thread_id;
end;
$$;

drop function if exists public.chat_respond_temp_guest(uuid, boolean);

create or replace function public.chat_respond_temp_guest(
    p_invite_id uuid,
    p_accept boolean
) returns void
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    current_user_id uuid := auth.uid();
    invite_rec public.chat_temp_guest_invites%rowtype;
    sanitized_duration integer;
    expiry_time timestamptz;
    visibility timestamptz := now();
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;

    select *
      into invite_rec
      from public.chat_temp_guest_invites
     where id = p_invite_id
       and status = 'pending';

    if invite_rec is null then
        raise exception 'Invite not found or already processed';
    end if;

    if invite_rec.guest_id <> current_user_id then
        raise exception 'You are not the invited guest';
    end if;

    if not p_accept then
        update public.chat_temp_guest_invites
           set status = 'declined',
               responded_at = now()
         where id = p_invite_id;

        delete from public.chat_thread_participants
         where thread_id = invite_rec.thread_id
           and user_id = invite_rec.guest_id
           and role = 'guest';

        update public.chat_threads
           set updated_at = now()
         where id = invite_rec.thread_id;
        return;
    end if;

    sanitized_duration := greatest(10, least(invite_rec.duration_minutes, 1440));
    expiry_time := now() + make_interval(mins => sanitized_duration);

    update public.chat_temp_guest_invites
       set status = 'accepted',
           responded_at = now(),
           expires_at = expiry_time
     where id = p_invite_id;

    insert into public.chat_guest_access (thread_id, guest_id, granted_by, added_at, expires_at, revoked_at)
    values (invite_rec.thread_id, invite_rec.guest_id, invite_rec.requested_by, now(), expiry_time, null)
    on conflict (thread_id, guest_id) do update
        set expires_at = excluded.expires_at,
            added_at = now(),
            granted_by = excluded.granted_by,
            revoked_at = null;

    perform public.chat_upsert_participant(
        invite_rec.thread_id,
        invite_rec.guest_id,
        'guest',
        invite_rec.requested_by,
        visibility
    );

    update public.chat_threads
       set updated_at = now()
     where id = invite_rec.thread_id;
end;
$$;

create or replace function public.chat_notify_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.chat_request_notification(
        p_event_type => 'message',
        p_thread_id => new.thread_id,
        p_actor_id => new.sender_id,
        p_reference_id => new.id,
        p_metadata => jsonb_build_object('message_type', new.message_type)
    );
    return new;
end;
$$;

drop trigger if exists chat_notify_message_ai on public.chat_messages;

create trigger chat_notify_message_ai
after insert on public.chat_messages
for each row
execute function public.chat_notify_on_message();

create or replace function public.chat_notify_on_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.chat_request_notification(
        p_event_type => 'reaction',
        p_thread_id => new.thread_id,
        p_actor_id => new.user_id,
        p_reference_id => new.message_id,
        p_metadata => jsonb_build_object(
            'reaction', new.reaction,
            'reaction_id', new.id
        )
    );
    return new;
end;
$$;

drop trigger if exists chat_notify_reaction_ai on public.chat_message_reactions;

create trigger chat_notify_reaction_ai
after insert on public.chat_message_reactions
for each row
execute function public.chat_notify_on_reaction();

do $$
begin
    if not exists (select 1 from cron.job where jobname = 'chat_expire_guest_access') then
        perform cron.schedule(
            'chat_expire_guest_access',
            '5 2 * * *',
            'select public.chat_expire_guest_access();'
        );
    end if;

    if not exists (select 1 from cron.job where jobname = 'chat_prune_temp_invites') then
        perform cron.schedule(
            'chat_prune_temp_invites',
            '15 * * * *',
            'select public.chat_prune_temp_invites();'
        );
    end if;

    if not exists (select 1 from cron.job where jobname = 'chat_cleanup_empty_threads') then
        perform cron.schedule(
            'chat_cleanup_empty_threads',
            '35 2 * * *',
            'select public.chat_cleanup_empty_threads();'
        );
    end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants so PostgREST can expose these RPCs to authenticated users
-- ---------------------------------------------------------------------------

grant execute on function public.chat_set_messaging_enabled(boolean) to authenticated;
grant select on table public.call_shared_media_state to authenticated;
grant select on table public.call_shared_media_events to authenticated;
grant execute on function public.call_shared_media_set_state(text, uuid, text, text, text, text, text, integer, text, integer, text, integer) to authenticated;
grant execute on function public.call_shared_media_get_state(uuid) to authenticated;
grant execute on function public.call_shared_media_get_state(uuid) to anon;
grant execute on function public.call_shared_media_list(text) to authenticated;

grant execute on function public.chat_list_threads() to authenticated;
grant execute on function public.chat_start_thread(uuid) to authenticated;
grant execute on function public.chat_send_message(uuid, text, text, text, text, jsonb) to authenticated;
grant execute on function public.chat_edit_message(uuid, text) to authenticated;
grant execute on function public.chat_delete_message(uuid) to authenticated;
grant execute on function public.chat_mark_thread_read(uuid) to authenticated;
grant execute on function public.chat_set_thread_mute(uuid, timestamptz) to authenticated;
grant execute on function public.chat_create_group(text, uuid[], text) to authenticated;
grant execute on function public.chat_add_participants(uuid, uuid[]) to authenticated;
grant execute on function public.chat_remove_participant(uuid, uuid) to authenticated;
grant execute on function public.chat_leave_group(uuid) to authenticated;
grant execute on function public.chat_update_group(uuid, text, text) to authenticated;
grant execute on function public.chat_request_temp_guest(uuid, uuid, integer) to authenticated;
grant execute on function public.chat_cancel_temp_guest(uuid) to authenticated;
grant execute on function public.chat_respond_temp_guest(uuid, boolean) to authenticated;

grant execute on function public.chat_list_threads() to anon;
grant execute on function public.chat_start_thread(uuid) to anon;
grant execute on function public.chat_send_message(uuid, text, text, text, text, jsonb) to anon;
grant execute on function public.chat_edit_message(uuid, text) to anon;
grant execute on function public.chat_delete_message(uuid) to anon;
grant execute on function public.chat_mark_thread_read(uuid) to anon;
grant execute on function public.chat_set_thread_mute(uuid, timestamptz) to anon;
grant execute on function public.chat_create_group(text, uuid[], text) to anon;
grant execute on function public.chat_add_participants(uuid, uuid[]) to anon;
grant execute on function public.chat_remove_participant(uuid, uuid) to anon;
grant execute on function public.chat_leave_group(uuid) to anon;
grant execute on function public.chat_update_group(uuid, text, text) to anon;
grant execute on function public.chat_request_temp_guest(uuid, uuid, integer) to anon;
grant execute on function public.chat_cancel_temp_guest(uuid) to anon;
grant execute on function public.chat_respond_temp_guest(uuid, boolean) to anon;

grant execute on function public.chat_expire_guest_access() to service_role;
grant execute on function public.chat_prune_temp_invites(integer) to service_role;
grant execute on function public.chat_cleanup_empty_threads() to service_role;
grant execute on function public.chat_remove_user(uuid) to service_role;
grant execute on function public.chat_sweep_orphan_users(integer) to service_role;
grant execute on function public.chat_collect_notification_targets(text, uuid, uuid, uuid, jsonb) to service_role;
grant execute on function public.chat_log_notifications(jsonb) to service_role;
grant execute on function public.chat_register_push_token(text, text, text, text, text) to authenticated;
grant execute on function public.chat_unregister_push_token(text) to authenticated;

commit;
create or replace function public.chat_send_message(
    p_thread_id uuid,
    p_body text default null,
    p_message_type text default 'text',
    p_attachment_url text default null,
    p_attachment_thumb_url text default null,
    p_attachment_metadata jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    inserted chat_messages;
    thread_is_group boolean;
    recipient_blocked boolean := false;
begin
    if current_user_id is null then
        raise exception 'Not authenticated';
    end if;
    if p_thread_id is null then
        raise exception 'Thread id required';
    end if;
    if coalesce(trim(p_body), '') = '' and coalesce(p_message_type, 'text') = 'text' then
        raise exception 'Message cannot be empty';
    end if;

    select is_group into thread_is_group
      from public.chat_threads
     where id = p_thread_id;

    if thread_is_group is null then
        raise exception 'Conversation not found';
    end if;

    if not exists (
        select 1
          from public.chat_thread_participants tp
         where tp.thread_id = p_thread_id
           and tp.user_id = current_user_id
    ) then
        raise exception 'You are not a participant of this thread';
    end if;

    if not thread_is_group then
        select exists (
            select 1
              from public.chat_thread_participants tp
              join public.public_profiles prof on prof.id = tp.user_id
             where tp.thread_id = p_thread_id
               and tp.user_id <> current_user_id
               and coalesce(prof.messaging_enabled, true) = false
        ) into recipient_blocked;

        if recipient_blocked then
            raise exception 'Recipient is not accepting messages right now';
        end if;
    end if;

    insert into public.chat_messages (
        thread_id,
        sender_id,
        body,
        message_type,
        attachment_url,
        attachment_thumb_url,
        attachment_metadata
    )
    values (
        p_thread_id,
        current_user_id,
        case when coalesce(p_message_type, 'text') = 'text' then trim(coalesce(p_body, '')) else coalesce(p_body, '') end,
        coalesce(p_message_type, 'text'),
        p_attachment_url,
        p_attachment_thumb_url,
        p_attachment_metadata
    )
    returning * into inserted;

    update public.chat_threads
       set updated_at = inserted.created_at
     where id = p_thread_id;

    update public.chat_thread_participants
       set last_read_at = inserted.created_at
     where thread_id = p_thread_id
       and user_id = current_user_id;

    return jsonb_build_object(
        'id', inserted.id,
        'thread_id', inserted.thread_id,
        'sender_id', inserted.sender_id,
        'body', inserted.body,
        'message_type', inserted.message_type,
        'attachment_url', inserted.attachment_url,
        'attachment_thumb_url', inserted.attachment_thumb_url,
        'attachment_metadata', inserted.attachment_metadata,
        'created_at', inserted.created_at,
        'edited_at', inserted.edited_at
    );
end;
$$;
create or replace function public.chat_thread_summary(p_thread_id uuid, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
set row_security = off
as $$
declare
    last_msg record;
    last_read timestamptz;
    current_mute timestamptz;
    current_role text;
    thread_rec record;
    unread_count integer := 0;
    participants_json jsonb := '[]'::jsonb;
    guest_access_json jsonb := '[]'::jsonb;
    pending_invite_json jsonb;
    has_pending boolean := false;
    current_ts timestamptz := now();
    viewer_visible_from timestamptz := timestamp 'epoch';
    viewer_enabled boolean := true;
    peer_disabled boolean := false;
begin
    select t.*, coalesce(pp.messaging_enabled, true) as viewer_enabled
      into thread_rec
      from public.chat_threads t
      left join public.public_profiles pp on pp.id = p_user
     where t.id = p_thread_id;

    if thread_rec.id is null then
        return null;
    end if;

    viewer_enabled := coalesce(thread_rec.viewer_enabled, true);

    select visible_from into viewer_visible_from
      from public.chat_thread_participants tp
     where tp.thread_id = p_thread_id
       and tp.user_id = p_user;

    viewer_visible_from := coalesce(viewer_visible_from, timestamp 'epoch');

    update public.chat_guest_access ga
       set revoked_at = coalesce(ga.revoked_at, current_ts)
     where ga.thread_id = p_thread_id
       and ga.revoked_at is null
       and ga.expires_at <= current_ts;

    delete from public.chat_thread_participants tp
     where tp.thread_id = p_thread_id
       and tp.role = 'guest'
       and not exists (
            select 1
              from public.chat_guest_access ga
             where ga.thread_id = tp.thread_id
               and ga.guest_id = tp.user_id
               and ga.revoked_at is null
               and ga.expires_at > current_ts
        );

    select m.sender_id, m.body, m.created_at, m.message_type, m.attachment_url, m.attachment_thumb_url
      into last_msg
      from public.chat_messages m
     where m.thread_id = p_thread_id
       and m.deleted_at is null
       and m.created_at >= viewer_visible_from
     order by m.created_at desc
     limit 1;

    select tp.last_read_at, tp.muted_until, tp.role
      into last_read, current_mute, current_role
      from public.chat_thread_participants tp
     where tp.thread_id = p_thread_id and tp.user_id = p_user;

    if last_read is null then
        select count(*) into unread_count
          from public.chat_messages m
         where m.thread_id = p_thread_id
           and m.deleted_at is null
           and m.created_at >= viewer_visible_from;
    else
        select count(*) into unread_count
          from public.chat_messages m
         where m.thread_id = p_thread_id
           and m.deleted_at is null
           and m.created_at >= greatest(last_read, viewer_visible_from);
    end if;

    select coalesce(jsonb_agg(
        jsonb_build_object(
            'user_id', tp.user_id,
            'username', coalesce(prof.username, 'Anonymous'),
            'avatar_url', prof.avatar_url,
            'last_read_at', tp.last_read_at,
            'last_typing_at', tp.last_typing_at,
            'muted_until', tp.muted_until,
            'is_muted', coalesce(tp.muted_until > current_ts, false),
            'role', tp.role,
            'invited_by', tp.invited_by,
            'joined_at', tp.joined_at,
            'visible_from', tp.visible_from,
            'messaging_enabled', coalesce(prof.messaging_enabled, true),
            'is_online', false,
            'presence_updated_at', null
        )
    ), '[]'::jsonb)
      into participants_json
      from public.chat_thread_participants tp
      left join public.public_profiles prof on prof.id = tp.user_id
     where tp.thread_id = p_thread_id;

    if thread_rec.is_group = false then
        select exists (
            select 1
              from public.chat_thread_participants tp
              left join public.public_profiles prof on prof.id = tp.user_id
             where tp.thread_id = p_thread_id
               and tp.user_id <> p_user
               and coalesce(prof.messaging_enabled, true) = false
        ) into peer_disabled;
    end if;

    select coalesce(jsonb_agg(
        jsonb_build_object(
            'thread_id', ga.thread_id,
            'guest_id', ga.guest_id,
            'added_at', ga.added_at,
            'expires_at', ga.expires_at,
            'granted_by', ga.granted_by,
            'revoked_at', ga.revoked_at,
            'guest_avatar_url', guest_prof.avatar_url
        )
    ), '[]'::jsonb)
      into guest_access_json
      from public.chat_guest_access ga
      left join public.public_profiles guest_prof on guest_prof.id = ga.guest_id
     where ga.thread_id = p_thread_id;

    select jsonb_build_object(
            'invite_id', inv.id,
            'thread_id', inv.thread_id,
            'guest_id', inv.guest_id,
            'requested_by', inv.requested_by,
            'duration_minutes', inv.duration_minutes,
            'created_at', inv.created_at
        )
      into pending_invite_json
      from public.chat_temp_guest_invites inv
     where inv.thread_id = p_thread_id
       and inv.guest_id = p_user
       and inv.status = 'pending'
     order by inv.created_at desc
     limit 1;

    select exists (
            select 1
              from public.chat_temp_guest_invites inv
             where inv.thread_id = p_thread_id
               and inv.status = 'pending'
        )
      into has_pending;

    return jsonb_build_object(
        'thread_id', p_thread_id,
        'created_at', thread_rec.created_at,
        'updated_at', thread_rec.updated_at,
        'is_group', thread_rec.is_group,
        'title', thread_rec.title,
        'avatar_url', thread_rec.avatar_url,
        'created_by', thread_rec.created_by,
        'last_message_at', coalesce(last_msg.created_at, thread_rec.updated_at),
        'last_message_text', last_msg.body,
        'last_sender_id', last_msg.sender_id,
        'last_read_at', last_read,
        'muted_until', current_mute,
        'is_muted', coalesce(current_mute > current_ts, false),
        'unread_count', unread_count,
        'last_message_type', last_msg.message_type,
        'last_attachment_url', last_msg.attachment_url,
        'last_attachment_thumb_url', last_msg.attachment_thumb_url,
        'current_role', current_role,
        'participants', participants_json,
        'guest_access', guest_access_json,
        'pending_invite', pending_invite_json,
        'has_pending_guest', has_pending,
        'viewer_visible_from', viewer_visible_from,
        'messaging_enabled', viewer_enabled,
        'messaging_allowed', case when thread_rec.is_group then true else not peer_disabled end
    );
end;
$$;
