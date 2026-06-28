# Database Schema

The Phase 2 schema lives in `supabase/migrations/001_phase2_schema.sql`. Phase 3
live duel RLS is in `003_phase3_live_duels.sql` and the friend-code live
challenge backend is in `006_friend_codes_live_duel_invites.sql`.

Core tables:

- `profiles`
- `topics`
- `questions`
- `matches`
- `match_players`
- `match_questions`
- `player_answers`
- `topic_user_stats`
- `daily_challenges`
- `daily_challenge_questions`
- `daily_challenge_results`
- `friend_challenges`
- `reports`
- `friendships` (friend request graph; see `006`)
- `live_duel_invites` (live friend duel room codes; see `006`)

Design notes:

- `profiles.id` references `auth.users(id)`.
- `profiles.friend_code` is the public, stable, unique lookup for friends. It is
  backfilled by the migration and defaulted for new profile rows via the
  `public.generate_friend_code()` generation helper. Friend code issuance is
  server-authoritative: the generator function is not granted to clients.
- Public gameplay data is read through approved/active rows.
- Match participation is modeled through `match_players`.
- Scores and stats are stored in safe aggregate tables for leaderboards.
- Server-authoritative scoring should write `player_answers`, `match_players`,
  `topic_user_stats`, and match winner/status in one trusted server-side
  operation. Streak scoring in `submit_match_answers` is computed in
  `match_questions.question_index` order.

## Friendships (`006_friend_codes_live_duel_invites.sql`)

`friendships(requester_id, addressee_id, status)` with `status` in
`pending | accepted | declined | cancelled`. A unique partial index on
`(least(requester_id, addressee_id), greatest(requester_id, addressee_id))`
where `status in ('pending','accepted')` enforces at most one active
relationship per pair. A `check (requester_id <> addressee_id)` prevents
self-friending.

## Live duel invites (`006_friend_codes_live_duel_invites.sql`)

`live_duel_invites(join_code, host_id, guest_id, match_id, topic_id, status,
expires_at)`. Status is `pending | accepted | expired | cancelled`. `join_code`
is unique. Indexes cover `join_code`, `(host_id, status)`, and
`(guest_id, status)`. Host creates the room; an atomically joined guest flips
both `match.status` to `in_progress` and the invite to `accepted`.

## Server-side RPCs (`006_friend_codes_live_duel_invites.sql`)

All SECURITY DEFINER with `search_path = public`, granted to `authenticated`:

- `ensure_friend_code()` → assigns+returns the caller's friend code if missing.
- `lookup_profile_by_friend_code(code text)` → safe public profile fields.
- `send_friend_request(code text)` → creates a pending `friendships` row by
  friend code, returns the active friendship id; rejects self-friending;
  reuses an existing pending/accepted request.
- `accept_friend_request(id uuid)` / `decline_friend_request(id uuid)` /
  `cancel_friend_request(id uuid)` → transition pending state for the
  recipient or requester only.
- `create_live_duel_invite(topic_id uuid)` → server-side creates a `live` match
  (status `waiting`), the host's `match_players` row, a fixed 7-question
  `match_questions` set, and the `live_duel_invites` row with a fresh
  `join_code`; returns `invite_id, match_id, join_code, topic_id, expires_at`.
- `join_live_duel_invite(code text)` → atomically sets the guest, inserts the
  second `match_players` row, moves the match to `in_progress`, and marks the
  invite `accepted`. `SELECT ... FOR UPDATE` plus `guest_id IS NULL`/status
  guards make concurrent joins safe: only one guest can succeed per code.

Live friend duels are networked-only: there is no bot/local fallback backend
path through these RPCs.
