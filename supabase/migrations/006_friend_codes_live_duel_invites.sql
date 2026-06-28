-- Gumrush live friend-code challenge: backend/schema/functions.
-- Adds public friend identity, friendships, live duel room codes, and the
-- server-side SQL RPCs that own the trusted mutation paths.
--
-- This migration is mostly additive and rerunnable — CREATE OR REPLACE function
-- and CREATE TABLE IF NOT EXISTS statements are safe to re-run, but plain
-- CREATE POLICY statements will error on re-run if the policies already exist.
-- It does not touch the iOS Swift
-- layer; the new contracts are exercised through Edge Functions / RPCs in
-- later parts. Scoring remains server-authoritative via submit_match_answers.

-- =============================================================================
-- Friend code on profiles (public lookup, NOT Apple ID/email)
-- =============================================================================

alter table public.profiles
  add column if not exists friend_code text unique;

-- Stable, collision-avoiding friend code generator.
-- Uses an unambiguous alphabet (no O/0/I/1) and retries until the code is
-- unused. SECURITY DEFINER so the lookup against profiles bypasses RLS during
-- collision checks; the function itself only reads friend_code.
create or replace function public.generate_friend_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
  attempt integer := 0;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(chars, 1 + floor(random() * 32)::int, 1);
    end loop;
    if not exists (select 1 from public.profiles where friend_code = code) then
      return code;
    end if;
    attempt := attempt + 1;
    if attempt > 25 then
      raise exception 'Could not generate a unique friend code after 25 attempts.';
    end if;
  end loop;
end;
$$;

revoke all on function public.generate_friend_code() from public;
-- Only the database and SECURITY DEFINER functions call the generator; do not
-- expose it to clients directly. Granting to authenticated is intentionally
-- omitted to keep friend code issuance server-authoritative.

-- Backfill friend codes for any existing profile rows that don't have one.
-- Runs as SECURITY DEFINER so the unique constraint collision loop works.
create or replace function public.backfill_friend_codes()
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  pid uuid;
  new_code text;
begin
  for pid in select id from public.profiles where friend_code is null loop
    new_code := public.generate_friend_code();
    update public.profiles set friend_code = new_code where id = pid and friend_code is null;
  end loop;
end;
$$;

revoke all on function public.backfill_friend_codes() from public;

do $$
begin
  perform public.backfill_friend_codes();
end $$;

drop function if exists public.backfill_friend_codes();

-- All existing rows now have a friend_code. Enforce it going forward.
alter table public.profiles
  alter column friend_code set not null;

-- Trigger to auto-assign friend codes on profile insert. SECURITY DEFINER so
-- the trigger body can call generate_friend_code() even though clients cannot.
-- Using a trigger rather than a DEFAULT expression avoids the requirement for
-- clients to hold EXECUTE on generate_friend_code().
create or replace function public.trg_set_friend_code()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.friend_code is null then
    NEW.friend_code := public.generate_friend_code();
  end if;
  return NEW;
end;
$$;

revoke all on function public.trg_set_friend_code() from public;

create trigger trg_set_friend_code
  before insert on public.profiles
  for each row
  execute function public.trg_set_friend_code();

-- =============================================================================
-- Friendships (normalized pending/accepted/declined/cancelled graph)
-- =============================================================================

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);

-- At most one active (pending or accepted) relationship per unordered pair.
-- Declined/cancelled rows may coexist so a later re-request can be tracked, but
-- the unique partial index prevents two pending requests or a pending + accepted.
create unique index if not exists uniq_friendships_active_pair
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id))
  where status in ('pending','accepted');

create index if not exists idx_friendships_addressee_status
  on public.friendships(addressee_id, status);

create index if not exists idx_friendships_requester_status
  on public.friendships(requester_id, status);

alter table public.friendships enable row level security;

create policy "friendships_read_involved"
on public.friendships for select
to authenticated
using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "friendships_insert_requester"
on public.friendships for insert
to authenticated
with check (requester_id = auth.uid() and status = 'pending');

create policy "friendships_update_involved"
on public.friendships for update
to authenticated
using (requester_id = auth.uid() or addressee_id = auth.uid())
with check (requester_id = auth.uid() or addressee_id = auth.uid());

-- =============================================================================
-- Live duel room codes
-- =============================================================================

create table if not exists public.live_duel_invites (
  id uuid primary key default gen_random_uuid(),
  join_code text unique not null,
  host_id uuid not null references public.profiles(id) on delete cascade,
  guest_id uuid references public.profiles(id) on delete set null,
  match_id uuid references public.matches(id) on delete cascade,
  topic_id uuid not null references public.topics(id),
  status text not null default 'pending'
    check (status in ('pending','accepted','expired','cancelled')),
  expires_at timestamptz not null default (now() + interval '15 minutes'),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  check (host_id <> guest_id)
);

create index if not exists idx_live_duel_invites_join_code
  on public.live_duel_invites(join_code);

create index if not exists idx_live_duel_invites_host_status
  on public.live_duel_invites(host_id, status);

create index if not exists idx_live_duel_invites_guest_status
  on public.live_duel_invites(guest_id, status);

alter table public.live_duel_invites enable row level security;

create policy "live_duel_invites_read_involved"
on public.live_duel_invites for select
to authenticated
using (host_id = auth.uid() or guest_id = auth.uid());

create policy "live_duel_invites_insert_host"
on public.live_duel_invites for insert
to authenticated
with check (host_id = auth.uid());

create policy "live_duel_invites_update_involved"
on public.live_duel_invites for update
to authenticated
using (host_id = auth.uid() or guest_id = auth.uid())
with check (host_id = auth.uid() or guest_id = auth.uid());

-- Stable, collision-avoiding room/join code generator. Defined after the
-- live_duel_invites table exists so static analysis tools can resolve the
-- table reference inside the loop.
create or replace function public.generate_join_code()
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  code text;
  attempt integer := 0;
begin
  loop
    code := '';
    for i in 1..4 loop
      code := code || substr(chars, 1 + floor(random() * 32)::int, 1);
    end loop;
    if not exists (select 1 from public.live_duel_invites where join_code = code) then
      return code;
    end if;
    attempt := attempt + 1;
    if attempt > 25 then
      raise exception 'Could not generate a unique join code after 25 attempts.';
    end if;
  end loop;
end;
$$;

revoke all on function public.generate_join_code() from public;

-- =============================================================================
-- Server-side RPC contract
-- All SECURITY DEFINER, search_path locked to public, granted to authenticated.
-- Business rules (no self-friending, no double-join, atomic match start) are
-- enforced here so clients cannot bypass them through RLS-permitted writes.
-- =============================================================================

-- Ensure the calling user has a friend code; returns it.
create or replace function public.ensure_friend_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing text;
  new_code text;
begin
  select friend_code into existing from public.profiles where id = auth.uid();
  if existing is not null then
    return existing;
  end if;

  new_code := public.generate_friend_code();
  -- Race-safe: only update if still null, then re-read what landed.
  update public.profiles
    set friend_code = new_code
    where id = auth.uid() and friend_code is null;

  select friend_code into existing from public.profiles where id = auth.uid();
  if existing is null then
    raise exception 'No profile found for the calling user.';
  end if;
  return existing;
end;
$$;

revoke all on function public.ensure_friend_code() from public;
grant execute on function public.ensure_friend_code() to authenticated;

-- Look up a public profile by friend code. Returns just the safe public fields.
create or replace function public.lookup_profile_by_friend_code(p_friend_code text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_seed text
)
language sql
stable
security definer
set search_path = public
as $$
  select id, username, display_name, avatar_seed
  from public.profiles
  where friend_code = upper(trim(p_friend_code));
$$;

revoke all on function public.lookup_profile_by_friend_code(text) from public;
grant execute on function public.lookup_profile_by_friend_code(text) to authenticated;

-- Send a friend request by friend code. Idempotent-ish: returns the active
-- friendship id if a pending/accepted relationship already exists.
create or replace function public.send_friend_request(p_friend_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  target_id uuid;
  existing_id uuid;
  new_id uuid;
begin
  if caller_id is null then
    raise exception 'Sign in before sending a friend request.';
  end if;

  select id into target_id from public.profiles where friend_code = upper(trim(p_friend_code));
  if target_id is null then
    raise exception 'No player found with that friend code.';
  end if;

  if target_id = caller_id then
    raise exception 'You cannot befriend yourself.';
  end if;

  -- Reuse an already-active relationship if one exists (regardless of direction).
  select id into existing_id
  from public.friendships
  where status in ('pending','accepted')
    and ((requester_id = caller_id and addressee_id = target_id)
         or (requester_id = target_id and addressee_id = caller_id))
  limit 1;

  if existing_id is not null then
    return existing_id;
  end if;

  -- A previously declined/cancelled request in the caller's outgoing direction
  -- can be replaced. The unique partial index only covers pending/accepted so
  -- this insert will not collide.
  insert into public.friendships (requester_id, addressee_id, status)
  values (caller_id, target_id, 'pending')
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.send_friend_request(text) from public;
grant execute on function public.send_friend_request(text) to authenticated;

-- Accept a friend request directed at the caller.
create or replace function public.accept_friend_request(p_friendship_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  row record;
begin
  select * into row
  from public.friendships
  where id = p_friendship_id
  for update;

  if row is null then
    raise exception 'Friend request not found.';
  end if;

  if row.addressee_id <> auth.uid() then
    raise exception 'Only the recipient can accept this friend request.';
  end if;

  if row.status <> 'pending' then
    raise exception 'This friend request is no longer pending.';
  end if;

  update public.friendships
    set status = 'accepted', responded_at = now()
    where id = p_friendship_id;

  return p_friendship_id;
end;
$$;

revoke all on function public.accept_friend_request(uuid) from public;
grant execute on function public.accept_friend_request(uuid) to authenticated;

-- Decline a friend request directed at the caller.
create or replace function public.decline_friend_request(p_friendship_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  row record;
begin
  select * into row from public.friendships where id = p_friendship_id for update;

  if row is null then
    raise exception 'Friend request not found.';
  end if;

  if row.addressee_id <> auth.uid() then
    raise exception 'Only the recipient can decline this friend request.';
  end if;

  if row.status <> 'pending' then
    raise exception 'This friend request is no longer pending.';
  end if;

  update public.friendships
    set status = 'declined', responded_at = now()
    where id = p_friendship_id;

  return p_friendship_id;
end;
$$;

revoke all on function public.decline_friend_request(uuid) from public;
grant execute on function public.decline_friend_request(uuid) to authenticated;

-- Cancel an outgoing pending friend request.
create or replace function public.cancel_friend_request(p_friendship_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  row record;
begin
  select * into row from public.friendships where id = p_friendship_id for update;

  if row is null then
    raise exception 'Friend request not found.';
  end if;

  if row.requester_id <> auth.uid() then
    raise exception 'Only the requester can cancel this friend request.';
  end if;

  if row.status <> 'pending' then
    raise exception 'This friend request is no longer pending.';
  end if;

  update public.friendships
    set status = 'cancelled', responded_at = now()
    where id = p_friendship_id;

  return p_friendship_id;
end;
$$;

revoke all on function public.cancel_friend_request(uuid) from public;
grant execute on function public.cancel_friend_request(uuid) to authenticated;

-- Create a live duel invite for a topic. Server-side it creates the match, the
-- host's match_players row, the fixed 7-question set, and the invite row with a
-- freshly generated join code. Returns the ids the client needs to subscribe to
-- realtime channels and share the code.
create or replace function public.create_live_duel_invite(p_topic_id uuid)
returns table (
  invite_id uuid,
  match_id uuid,
  join_code text,
  topic_id uuid,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  v_match_id uuid;
  v_invite_id uuid;
  v_join_code text;
  v_expires timestamptz := now() + interval '15 minutes';
  v_topic_exists boolean;
  q record;
  idx integer := 0;
begin
  if caller_id is null then
    raise exception 'Sign in before creating a live duel.';
  end if;

  select exists(select 1 from public.topics where id = p_topic_id and status = 'active')
    into v_topic_exists;
  if not v_topic_exists then
    raise exception 'Topic is not available for live duels.';
  end if;

  -- Materialize the match shell first.
  insert into public.matches (topic_id, match_type, status, created_by)
  values (p_topic_id, 'live', 'waiting', caller_id)
  returning id into v_match_id;

  -- Host occupies slot 1 (creator convention, consistent with async matches).
  insert into public.match_players (match_id, user_id, player_slot)
  values (v_match_id, caller_id, 1);

  -- Fixed 7-question set, randomly drawn from approved questions in the topic.
  -- The questions table is aliased because RETURNS TABLE exposes pl/pgsql
  -- variables (topic_id, match_id, ...) that would otherwise shadow the bare
  -- column names and make the WHERE clause ambiguous.
  idx := 0;
  for q in
    select qs.id as question_id
    from public.questions qs
    where qs.topic_id = p_topic_id and qs.status = 'approved'
    order by random()
    limit 7
  loop
    insert into public.match_questions (match_id, question_id, question_index)
    values (v_match_id, q.question_id, idx);
    idx := idx + 1;
  end loop;

  if idx < 7 then
    -- Not enough approved questions in this topic. Roll back so the host does
    -- not end up with a broken room code.
    raise exception 'Topic does not have enough approved questions for a live duel.';
  end if;

  v_join_code := public.generate_join_code();

  insert into public.live_duel_invites (join_code, host_id, match_id, topic_id, status, expires_at)
  values (v_join_code, caller_id, v_match_id, p_topic_id, 'pending', v_expires)
  returning id into v_invite_id;

  return query select v_invite_id, v_match_id, v_join_code, p_topic_id, v_expires;
end;
$$;

revoke all on function public.create_live_duel_invite(uuid) from public;
grant execute on function public.create_live_duel_invite(uuid) to authenticated;

-- Join a live duel invite by room code atomically. Sets the guest, adds the
-- second match_players row, and flips the match to in_progress. SELECT ... FOR
-- UPDATE on the invite makes concurrent joins race on a single row lock, so at
-- most one guest can succeed for a given code.
create or replace function public.join_live_duel_invite(p_join_code text)
returns table (
  invite_id uuid,
  match_id uuid,
  host_id uuid,
  topic_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  row record;
begin
  if caller_id is null then
    raise exception 'Sign in before joining a live duel.';
  end if;

  select * into row
  from public.live_duel_invites
  where join_code = upper(trim(p_join_code))
  for update;

  if row is null then
    raise exception 'No live duel room found with that code.';
  end if;

  if row.host_id = caller_id then
    raise exception 'You cannot join your own live duel room.';
  end if;

  if row.status <> 'pending' then
    raise exception 'This live duel room is no longer open.';
  end if;

  if now() > row.expires_at then
    update public.live_duel_invites set status = 'expired' where id = row.id;
    raise exception 'This live duel room has expired.';
  end if;

  if row.guest_id is not null then
    raise exception 'This live duel room is already full.';
  end if;

  -- Insert the guest as player slot 2 (joined-player convention).
  -- The unique(match_id, user_id) constraint would also catch a duplicate join,
  -- but the row lock above makes the second caller fail cleanly.
  insert into public.match_players (match_id, user_id, player_slot)
  values (row.match_id, caller_id, 2);

  -- Open the match.
  update public.matches
    set status = 'in_progress', started_at = now()
    where id = row.match_id;

  -- Accept the invite.
  update public.live_duel_invites
    set guest_id = caller_id, status = 'accepted', accepted_at = now()
    where id = row.id;

  return query select row.id, row.match_id, row.host_id, row.topic_id;
end;
$$;

revoke all on function public.join_live_duel_invite(text) from public;
grant execute on function public.join_live_duel_invite(text) to authenticated;