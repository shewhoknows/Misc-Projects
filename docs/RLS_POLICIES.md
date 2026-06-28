# RLS Policies

RLS lives in `supabase/migrations/002_phase2_rls.sql`, with Phase 3 live duel
policies in `003_phase3_live_duels.sql` and `005_live_waiting_question_visibility.sql`,
and friend/friendship/live-duel-invite policies in `006_friend_codes_live_duel_invites.sql`.

Policy summary:

- Authenticated users can read active topics and approved questions.
- Authenticated users can read profiles.
- Users can insert/update only their own profile.
- Users can read matches where they are a participant.
- Users can create matches as themselves.
- Users can insert/update their own `match_players` row.
- Users can insert answers only for themselves.
- Users cannot edit questions.
- Authenticated users can insert reports.
- Leaderboard data is readable through safe profile/stat fields.
- `friendships`: only rows involving `auth.uid()` are readable; only the
  requester can insert (status `pending`); only involved users can update.
  Business rules (no self-friending, duplicate prevention) are enforced by
  `006` SECURITY DEFINER RPCs and the `uniq_friendships_active_pair` partial
  unique index.
- `live_duel_invites`: only rows where the caller is host or guest are
  readable/insertable (host only)/updatable. Atomic accept/double-join
  prevention is enforced by `join_live_duel_invite` SELECT ... FOR UPDATE RPC
  plus the unique `(match_id, user_id)` `match_players` constraint.

The iOS app uses only the anon key. Never expose service role keys to the client.
