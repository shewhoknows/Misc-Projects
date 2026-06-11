# Misc Projects

## FitTrack AI

A mobile-first fat-loss calorie tracking MVP inspired by MyFitnessPal.

Open `fittrack-ai/index.html`, or serve the repository root and visit
`/fittrack-ai/`.

### Features

- Login/signup demo flow
- Clean onboarding with BMR, TDEE, fat-loss calorie target, macro targets, and
  estimated weekly loss
- Dashboard with calories consumed, calories remaining, macros, exercise burn,
  water, weight progress, streak, adherence, and weekly average
- Manual meal logging and exercise logging
- AI meal photo and voice logging placeholders with editable review before save
- Progress charts, measurements, progress photos, weekly summary, insights,
  settings, and profile screens
- LocalStorage persistence for MVP data
- SQL schema in `fittrack-ai/schema.sql`

## fitness-plan.html

A self-contained 3-week fitness tracking page (May 21 – June 12, 2026). Just
open the file in any modern browser — no build step, no server.

### Features

- **Daily checklist** for strength workouts and 30-minute walks
- **Weigh-in tracking** on Day 1, two mid-cycle checkpoints, and the final day
- **Live progress bar** showing percentage of completed sessions
- **Latest weight display** with delta from target
- **Today's row** highlighted automatically and scrolled into view
- **Completed days** marked with a green left border once both checkboxes are ticked
- **localStorage persistence** — your progress survives page reloads
- **Dark mode** via `prefers-color-scheme`
- **Print-friendly** stylesheet for a clean paper copy
- **Accessible** — labeled checkboxes/inputs and visible focus rings

### Routines

Four bodyweight circuits are detailed at the bottom of the page:

- **Routine A** — Lower + Core
- **Routine B** — Upper + Core
- **Routine C** — Glutes & Legs
- **Routine D** — Pilates Core

Each is 3 rounds with 30–45s rest between exercises.

### Resetting

Use the **Reset all data** button to clear saved progress and weight entries
(asks for confirmation).
