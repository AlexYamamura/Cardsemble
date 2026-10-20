create table if not exists card_catalog (
  id text primary key,
  data jsonb not null,
  updated_at timestamptz not null default now()
);