-- Общий рейтинг «Не сегодня». Вставьте целиком в Supabase -> SQL Editor -> Run.
-- Скрипт можно запускать повторно: он ничего не ломает.

-- 1. Таблица: одна строка на игрока (лучший результат)
create table if not exists public.scores (
  id         text primary key check (char_length(id) between 1 and 64),
  name       text not null check (char_length(name) between 1 and 16),
  score      int  not null check (score >= 0),
  wave       int  not null check (wave >= 0),
  coop       boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists scores_score_idx on public.scores (score desc);

-- 2. RLS: включена; анонимам разрешено только читать
alter table public.scores enable row level security;

drop policy if exists "scores_select_anon" on public.scores;
create policy "scores_select_anon"
  on public.scores
  for select
  to anon
  using (true);

-- Права на таблицу: только SELECT, никакой прямой записи
revoke all on table public.scores from anon, authenticated;
grant select on table public.scores to anon, authenticated;

-- 3. Единственный путь записи: функция submit_score
create or replace function public.submit_score(
  p_id    text,
  p_name  text,
  p_score int,
  p_wave  int,
  p_coop  boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if p_id is null or char_length(p_id) < 1 or char_length(p_id) > 64 then
    raise exception 'bad id';
  end if;
  if char_length(v_name) < 1 then
    raise exception 'bad name';
  end if;
  v_name := left(v_name, 16);  -- длинное имя обрезаем
  if p_score is null or p_score < 0 or p_score >= 10000000 then
    raise exception 'bad score';
  end if;
  if p_wave is null or p_wave < 0 or p_wave > 100000 then
    raise exception 'bad wave';
  end if;

  insert into public.scores as s (id, name, score, wave, coop, updated_at)
  values (p_id, v_name, p_score, p_wave, coalesce(p_coop, false), now())
  on conflict (id) do update set
    name       = excluded.name,                       -- имя обновляется всегда
    score      = case when excluded.score > s.score then excluded.score else s.score end,
    wave       = case when excluded.score > s.score then excluded.wave  else s.wave  end,
    coop       = case when excluded.score > s.score then excluded.coop  else s.coop  end,
    updated_at = now();
end;
$$;

-- Вызывать функцию может только anon (и вошедшие пользователи), не PUBLIC
revoke all on function public.submit_score(text, text, int, int, boolean) from public;
grant execute on function public.submit_score(text, text, int, int, boolean) to anon, authenticated;
