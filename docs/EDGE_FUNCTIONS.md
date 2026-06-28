# Edge Functions

## `submit_match_answers`

Location:

- `supabase/functions/submit_match_answers/index.ts`

This is the server-authoritative scoring path for async matches. The iOS app
calls it first for remote submissions and falls back to direct table writes only
for local/dev resilience if the function is unavailable.

1. Receive `match_id`, raw selected options, and answer times.
2. Confirm the caller is authenticated.
3. Confirm the caller is a participant in the match.
4. Fetch canonical questions and correct options from `questions`.
5. Calculate:
   - correctness
   - answer points
   - speed bonus
   - streak bonus
   - XP gained
6. Insert `player_answers`.
7. Update the caller's `match_players` row.
8. If both players completed, resolve winner and mark match `completed`.
9. Update `topic_user_stats` and `profiles.total_xp`.

Streak scoring is computed in `match_questions.question_index` order: the
function fetches the match's fixed question list ordered by `question_index`
and sorts the canonical question set the same way before scoring, so the streak
bonus is deterministic across submissions.

## Friend-code / live duel RPCs

The friend-code live challenge backend is implemented as SQL RPCs (SECURITY
DEFINER, `search_path = public`) in `supabase/migrations/006_friend_codes_live_duel_invites.sql`
rather than Edge Functions. The iOS app invokes them via `supabase.rpc(...)`:

- `ensure_friend_code()`
- `lookup_profile_by_friend_code(code text)`
- `send_friend_request(code text)`
- `accept_friend_request(id uuid)` / `decline_friend_request(id uuid)` /
  `cancel_friend_request(id uuid)`
- `create_live_duel_invite(topic_id uuid)` — server-side creates the match,
  the host participant row, the fixed 7-question set, and the room invite with
  a fresh `join_code`.
- `join_live_duel_invite(code text)` — atomic guest join + match start.

Live friend duels are networked-only; there is no bot/local fallback backend
path for these RPCs.

## Deploy

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
supabase functions deploy submit_match_answers
```

Required secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Supabase provides the first two automatically in hosted functions. Set the
service role key only in function secrets.

## Current Phase 2 Status

The Edge Function scaffold is implemented and the app is wired to call it before
using the direct PostgREST fallback. Live verification requires migrations to be
applied and the function deployed to the project.
