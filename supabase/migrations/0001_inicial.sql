-- Controle Financeiro Pessoal — esquema inicial (Supabase / Postgres)
-- Rode uma vez no SQL Editor do projeto Supabase (ou com `supabase db push`).
--
-- Modelo: um "lar" (household) reúne as pessoas que compartilham os dados.
-- grupos (por ano) → itens → valores (um valor por item por mês).
-- Nada é apagado de verdade: exclusões viram `excluido = true`, para que a
-- exclusão também chegue aos outros aparelhos pela sincronização.

create extension if not exists pgcrypto;

-- ---------- tabelas ----------
create table public.lares (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null default 'Nossa casa',
  meta_pct    numeric(5,2) not null default 30 check (meta_pct between 0 and 100),
  codigo      text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid()
);

create table public.membros (
  lar_id   uuid not null references public.lares(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now(),
  primary key (lar_id, user_id)
);
create index membros_user_idx on public.membros(user_id);

create table public.grupos (
  id          uuid primary key,
  lar_id      uuid not null references public.lares(id) on delete cascade,
  ano         int  not null check (ano between 2000 and 2100),
  nome        text not null,
  tipo        text not null check (tipo in ('receita', 'despesa', 'investimento')),
  ordem       double precision not null default 0,
  excluido    boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid()
);
create index grupos_sync_idx on public.grupos(lar_id, updated_at);

create table public.itens (
  id          uuid primary key,
  lar_id      uuid not null references public.lares(id) on delete cascade,
  grupo_id    uuid not null references public.grupos(id) on delete cascade,
  nome        text not null,
  ordem       double precision not null default 0,
  excluido    boolean not null default false,
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid()
);
create index itens_sync_idx on public.itens(lar_id, updated_at);

create table public.valores (
  item_id     uuid not null references public.itens(id) on delete cascade,
  mes         smallint not null check (mes between 0 and 11),   -- 0 = janeiro
  lar_id      uuid not null references public.lares(id) on delete cascade,
  valor       numeric(14,2) not null default 0,
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid(),
  primary key (item_id, mes)
);
create index valores_sync_idx on public.valores(lar_id, updated_at);

-- ---------- updated_at/updated_by sempre pelo servidor ----------
create or replace function public.tocar() returns trigger
language plpgsql as $$
begin
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end $$;

create trigger lares_tocar   before insert or update on public.lares   for each row execute function public.tocar();
create trigger grupos_tocar  before insert or update on public.grupos  for each row execute function public.tocar();
create trigger itens_tocar   before insert or update on public.itens   for each row execute function public.tocar();
create trigger valores_tocar before insert or update on public.valores for each row execute function public.tocar();

-- ---------- acesso: só membros do lar ----------
create or replace function public.e_membro(p_lar uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membros where lar_id = p_lar and user_id = auth.uid());
$$;

alter table public.lares   enable row level security;
alter table public.membros enable row level security;
alter table public.grupos  enable row level security;
alter table public.itens   enable row level security;
alter table public.valores enable row level security;

create policy lares_ler      on public.lares   for select to authenticated using (public.e_membro(id));
create policy lares_alterar  on public.lares   for update to authenticated using (public.e_membro(id)) with check (public.e_membro(id));
create policy membros_ler    on public.membros for select to authenticated using (user_id = auth.uid() or public.e_membro(lar_id));

create policy grupos_ler     on public.grupos  for select to authenticated using (public.e_membro(lar_id));
create policy grupos_inserir on public.grupos  for insert to authenticated with check (public.e_membro(lar_id));
create policy grupos_alterar on public.grupos  for update to authenticated using (public.e_membro(lar_id)) with check (public.e_membro(lar_id));

create policy itens_ler      on public.itens   for select to authenticated using (public.e_membro(lar_id));
create policy itens_inserir  on public.itens   for insert to authenticated with check (public.e_membro(lar_id));
create policy itens_alterar  on public.itens   for update to authenticated using (public.e_membro(lar_id)) with check (public.e_membro(lar_id));

create policy valores_ler     on public.valores for select to authenticated using (public.e_membro(lar_id));
create policy valores_inserir on public.valores for insert to authenticated with check (public.e_membro(lar_id));
create policy valores_alterar on public.valores for update to authenticated using (public.e_membro(lar_id)) with check (public.e_membro(lar_id));
-- Sem políticas de DELETE: exclusão é lógica (excluido = true).

-- ---------- criar lar / entrar com código ----------
create or replace function public.criar_lar(p_nome text default 'Nossa casa') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  insert into public.lares(nome) values (coalesce(nullif(trim(p_nome), ''), 'Nossa casa')) returning id into v_id;
  insert into public.membros(lar_id, user_id) values (v_id, auth.uid());
  return v_id;
end $$;

create or replace function public.entrar_no_lar(p_codigo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Não autenticado'; end if;
  select id into v_id from public.lares where codigo = upper(trim(p_codigo));
  if v_id is null then raise exception 'Código de convite inválido'; end if;
  insert into public.membros(lar_id, user_id) values (v_id, auth.uid()) on conflict do nothing;
  return v_id;
end $$;

revoke all on function public.criar_lar(text)     from public, anon;
revoke all on function public.entrar_no_lar(text) from public, anon;
grant execute on function public.criar_lar(text)     to authenticated;
grant execute on function public.entrar_no_lar(text) to authenticated;

-- ---------- tempo real (o app relê quando algo muda) ----------
alter publication supabase_realtime add table public.lares, public.grupos, public.itens, public.valores;
