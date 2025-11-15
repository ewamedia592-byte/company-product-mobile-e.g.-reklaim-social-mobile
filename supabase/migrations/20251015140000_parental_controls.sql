begin;

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

alter table public.public_profiles
  add column if not exists birthdate date,
  add column if not exists is_minor boolean,
  add column if not exists parent_contact text,
  add column if not exists parent_consent_status text check (parent_consent_status in ('not_required','pending','approved','denied')) default 'not_required',
  add column if not exists parent_consent_at timestamptz,
  add column if not exists parent_consent_method text,
  add column if not exists onboarding_completed boolean not null default false;

create table if not exists public.parental_consent_requests (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references auth.users(id) on delete cascade,
  parent_email text not null,
  token text not null unique,
  status text not null check (status in ('pending','approved','denied','expired')) default 'pending',
  scope text[] not null default array['account','personalized_feed'],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  parent_user_id uuid references auth.users(id)
);

create index if not exists parental_consent_requests_child_idx on public.parental_consent_requests(child_id);
create index if not exists parental_consent_requests_token_idx on public.parental_consent_requests(token);

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'parental_consent_requests_set_updated_at'
  ) then
    create trigger parental_consent_requests_set_updated_at
      before update on public.parental_consent_requests
      for each row execute function public.handle_updated_at();
  end if;
end;
$$;

alter table public.parental_consent_requests enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'parental_consent_requests_insert'
      and tablename = 'parental_consent_requests'
      and schemaname = 'public'
  ) then
    create policy parental_consent_requests_insert
      on public.parental_consent_requests
      for insert
      with check (auth.uid() = child_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where policyname = 'parental_consent_requests_select_child'
      and tablename = 'parental_consent_requests'
      and schemaname = 'public'
  ) then
    create policy parental_consent_requests_select_child
      on public.parental_consent_requests
      for select
      using (auth.uid() = child_id);
  end if;
end;
$$;

create or replace function public.request_parental_consent(
  p_parent_email text,
  p_scope text[] default array['account','personalized_feed']
) returns public.parental_consent_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  _uid uuid := auth.uid();
  _profile record;
  _token text;
  _needs_consent boolean;
  _request public.parental_consent_requests;
begin
  if _uid is null then
    raise exception 'Not signed in';
  end if;

  select birthdate, parent_consent_status into _profile
  from public.public_profiles where id = _uid;

  if _profile.birthdate is null then
    raise exception 'Birthdate not set';
  end if;

  _needs_consent := age(now(), _profile.birthdate) < interval '18 years';
  if not _needs_consent then
    raise exception 'Consent not required';
  end if;

  _token := encode(gen_random_bytes(18), 'hex');

  insert into public.parental_consent_requests(child_id, parent_email, token, scope)
    values (_uid, lower(trim(p_parent_email)), _token, p_scope)
    returning * into _request;

  update public.public_profiles
     set parent_contact = lower(trim(p_parent_email)),
         parent_consent_status = 'pending',
         parent_consent_at = null,
         parent_consent_method = 'email',
         is_minor = true
   where id = _uid;

  return _request;
end;
$$;

create or replace function public.respond_parental_consent(
  p_token text,
  p_decision text,
  p_parent_user uuid default null
) returns public.parental_consent_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  _request public.parental_consent_requests;
  _decision text := lower(trim(p_decision));
begin
  if coalesce(p_token, '') = '' then
    raise exception 'Token required';
  end if;

  select * into _request
  from public.parental_consent_requests
  where token = lower(trim(p_token));

  if not found then
    raise exception 'Invalid or expired token';
  end if;

  if _request.status <> 'pending' then
    return _request;
  end if;

  if _decision not in ('approved', 'denied') then
    raise exception 'Decision must be approved or denied';
  end if;

  update public.parental_consent_requests
     set status = _decision,
         responded_at = now(),
         parent_user_id = coalesce(p_parent_user, parent_user_id)
   where id = _request.id
   returning * into _request;

  if _decision = 'approved' then
    update public.public_profiles
       set parent_consent_status = 'approved',
           parent_consent_at = now(),
           parent_consent_method = 'email',
           is_minor = true
     where id = _request.child_id;
    if p_parent_user is not null then
      insert into public.parent_child_links(parent_id, child_id)
        values (p_parent_user, _request.child_id)
        on conflict (parent_id, child_id) do update set updated_at = now();
    end if;
  else
    update public.public_profiles
       set parent_consent_status = 'denied',
           parent_consent_at = now(),
           parent_consent_method = 'email',
           is_minor = true
     where id = _request.child_id;
  end if;

  return _request;
end;
$$;

create table if not exists public.parent_child_links (
  parent_id uuid not null references auth.users(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  allow_ai_feed boolean not null default false,
  daily_time_limit_minutes integer,
  notifications_quiet_start time,
  notifications_quiet_end time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (parent_id, child_id)
);

do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname = 'parent_child_links_set_updated_at'
  ) then
    create trigger parent_child_links_set_updated_at
      before update on public.parent_child_links
      for each row execute function public.handle_updated_at();
  end if;
end;
$$;

alter table public.parent_child_links enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'parent_child_links_parent_manage'
      and tablename = 'parent_child_links'
      and schemaname = 'public'
  ) then
    create policy parent_child_links_parent_manage
      on public.parent_child_links
      for all
      using (parent_id = auth.uid())
      with check (parent_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where policyname = 'parent_child_links_child_select'
      and tablename = 'parent_child_links'
      and schemaname = 'public'
  ) then
    create policy parent_child_links_child_select
      on public.parent_child_links
      for select
      using (child_id = auth.uid());
  end if;
end;
$$;

create or replace function public.fetch_parent_children()
returns table(
  child_id uuid,
  username text,
  birthdate date,
  parent_consent_status text,
  allow_ai_feed boolean,
  daily_time_limit_minutes integer,
  notifications_quiet_start time,
  notifications_quiet_end time
)
language sql
security definer
set search_path = public
as $$
  select
    pcl.child_id,
    pp.username,
    pp.birthdate,
    pp.parent_consent_status,
    pcl.allow_ai_feed,
    pcl.daily_time_limit_minutes,
    pcl.notifications_quiet_start,
    pcl.notifications_quiet_end
  from public.parent_child_links pcl
  join public.public_profiles pp on pp.id = pcl.child_id
  where pcl.parent_id = auth.uid();
$$;

create or replace function public.update_parent_child_settings(
  p_child_id uuid,
  p_allow_ai_feed boolean,
  p_daily_time_limit_minutes integer,
  p_notifications_quiet_start time,
  p_notifications_quiet_end time
) returns public.parent_child_links
language plpgsql
security definer
set search_path = public
as $$
declare
  _updated public.parent_child_links;
begin
  update public.parent_child_links
     set allow_ai_feed = coalesce(p_allow_ai_feed, allow_ai_feed),
         daily_time_limit_minutes = p_daily_time_limit_minutes,
         notifications_quiet_start = p_notifications_quiet_start,
         notifications_quiet_end = p_notifications_quiet_end
   where parent_id = auth.uid()
     and child_id = p_child_id
   returning * into _updated;

  if not found then
    raise exception 'Child not linked to this parent';
  end if;

  return _updated;
end;
$$;

commit;
