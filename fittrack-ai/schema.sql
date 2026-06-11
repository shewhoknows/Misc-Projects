create table users (
  id uuid primary key,
  email text unique not null,
  password_hash text not null,
  name text not null,
  age integer not null,
  gender text not null,
  height_cm numeric not null,
  current_weight_kg numeric not null,
  goal_weight_kg numeric not null,
  activity_level text not null,
  dietary_preferences text[] default '{}',
  units text not null default 'metric',
  created_at timestamptz not null default now()
);

create table goals (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  maintenance_calories integer not null,
  calorie_target integer not null,
  protein_target_g integer not null,
  carbs_target_g integer not null,
  fat_target_g integer not null,
  fat_loss_speed text not null,
  estimated_weekly_loss_kg numeric not null,
  created_at timestamptz not null default now()
);

create table meals (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  meal_type text not null,
  logged_at timestamptz not null,
  source text not null default 'manual',
  total_calories integer not null default 0,
  total_protein_g numeric not null default 0,
  total_carbs_g numeric not null default 0,
  total_fat_g numeric not null default 0
);

create table food_items (
  id uuid primary key,
  meal_id uuid not null references meals(id) on delete cascade,
  food_name text not null,
  quantity text not null,
  calories integer not null,
  protein_g numeric not null default 0,
  carbs_g numeric not null default 0,
  fat_g numeric not null default 0
);

create table exercise_logs (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  exercise_type text not null,
  duration_minutes integer not null,
  intensity text not null,
  calories_burned integer not null,
  logged_at timestamptz not null
);

create table weight_logs (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  weight_kg numeric not null,
  logged_at timestamptz not null
);

create table progress_photos (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  image_url text not null,
  caption text,
  logged_at timestamptz not null
);

create table daily_summaries (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  summary_date date not null,
  calories_consumed integer not null default 0,
  protein_g numeric not null default 0,
  carbs_g numeric not null default 0,
  fat_g numeric not null default 0,
  exercise_calories integer not null default 0,
  water_cups integer not null default 0,
  adherence_score integer not null default 0,
  unique(user_id, summary_date)
);

create table ai_meal_estimates (
  id uuid primary key,
  user_id uuid not null references users(id) on delete cascade,
  meal_id uuid references meals(id) on delete set null,
  source text not null,
  raw_input text,
  detected_foods jsonb not null,
  confidence_score numeric not null,
  reviewed_by_user boolean not null default false,
  created_at timestamptz not null default now()
);
