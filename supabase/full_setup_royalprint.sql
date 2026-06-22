-- ============================================================================
-- ROYAL PRINT — SETUP COMPLETO (rodar UMA vez no SQL Editor do Supabase)
-- Banco: skacswwfbbdbtabgqsqy (cloud). Cria schema do app + org + 5 logins.
-- As tabelas do app (organizations, profiles, conversations...) NAO colidem
-- com as do bot (atendimentos, disparos, n8n_chat_histories...).
-- Senha inicial dos 5 usuarios: RoyalPrint@2026  (troquem depois)
-- ============================================================================

-- ===== 0001_init.sql =====
-- =====================================================================
-- Chatmix clone — schema inicial (multi-tenant + RLS)
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Organizações (inquilinos / tenants)
-- ---------------------------------------------------------------------
create table organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  document    text,                       -- CNPJ
  settings    jsonb not null default '{}',
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Perfis (atendentes / usuários) — 1:1 com auth.users
-- ---------------------------------------------------------------------
create table profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  organization_id uuid references organizations (id) on delete cascade,
  name            text not null default '',
  email           text,
  role            text not null default 'agent' check (role in ('admin','supervisor','agent')),
  department_id   uuid,
  avatar_url      text,
  status          text not null default 'offline' check (status in ('online','away','offline')),
  whatsapp        text,
  notify          boolean not null default true,
  created_at      timestamptz not null default now()
);

-- Função helper: org do usuário autenticado (SECURITY DEFINER evita recursão de RLS).
create or replace function current_org_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from profiles where id = auth.uid();
$$;

create or replace function current_role_is(target text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from profiles where id = auth.uid() and role = target);
$$;

-- ---------------------------------------------------------------------
-- Departamentos
-- ---------------------------------------------------------------------
create table departments (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  color           text default '#00a8ff',
  created_at      timestamptz not null default now()
);
alter table profiles
  add constraint profiles_department_fk
  foreign key (department_id) references departments (id) on delete set null;

-- ---------------------------------------------------------------------
-- Canais (conexões WhatsApp)
-- ---------------------------------------------------------------------
create table channels (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  type            text not null check (type in ('meta_cloud','uazapi')),
  phone           text,
  status          text not null default 'pending'
                    check (status in ('pending','connecting','connected','disconnected','error')),
  external_id     text,                    -- phone_number_id (Meta) ou instance (UAZAPI)
  credentials     jsonb not null default '{}',  -- tokens/segredos (criptografar em camada de app)
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Contatos (clientes)
-- ---------------------------------------------------------------------
create table contacts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text,
  phone           text not null,
  avatar_url      text,
  custom_fields   jsonb not null default '{}',
  notes           text,
  created_at      timestamptz not null default now(),
  unique (organization_id, phone)
);

-- ---------------------------------------------------------------------
-- Conversas (atendimentos)
-- ---------------------------------------------------------------------
create table conversations (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  channel_id       uuid not null references channels (id) on delete cascade,
  contact_id       uuid not null references contacts (id) on delete cascade,
  status           text not null default 'queued'
                     check (status in ('bot','queued','open','closed')),
  assigned_user_id uuid references profiles (id) on delete set null,
  department_id    uuid references departments (id) on delete set null,
  protocol         text,
  last_message_at  timestamptz,
  opened_at        timestamptz default now(),
  closed_at        timestamptz,
  satisfaction     int,
  created_at       timestamptz not null default now()
);
create index on conversations (organization_id, status, last_message_at desc);

-- ---------------------------------------------------------------------
-- Mensagens
-- ---------------------------------------------------------------------
create table messages (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  conversation_id uuid not null references conversations (id) on delete cascade,
  direction       text not null check (direction in ('in','out')),
  sender_type     text not null check (sender_type in ('contact','agent','bot','system')),
  sender_id       uuid,                    -- profile id se agente
  content_type    text not null default 'text'
                    check (content_type in ('text','image','audio','video','document','location','contact','template','sticker')),
  body            text,
  media_url       text,
  status          text not null default 'sent'
                    check (status in ('pending','sent','delivered','read','failed')),
  external_id     text,                    -- id da mensagem no provedor
  created_at      timestamptz not null default now()
);
create index on messages (conversation_id, created_at);

-- ---------------------------------------------------------------------
-- Tags / classificações (atendimento, cliente, status)
-- ---------------------------------------------------------------------
create table tags (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  color           text default '#00a8ff',
  scope           text not null default 'conversation'
                    check (scope in ('conversation','contact','status')),
  created_at      timestamptz not null default now()
);
create table conversation_tags (
  conversation_id uuid not null references conversations (id) on delete cascade,
  tag_id          uuid not null references tags (id) on delete cascade,
  primary key (conversation_id, tag_id)
);
create table contact_tags (
  contact_id uuid not null references contacts (id) on delete cascade,
  tag_id     uuid not null references tags (id) on delete cascade,
  primary key (contact_id, tag_id)
);

-- ---------------------------------------------------------------------
-- Mensagens rápidas / modelos / macros
-- ---------------------------------------------------------------------
create table quick_replies (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  title           text not null,
  content         text not null,
  shortcut        text,
  kind            text not null default 'model' check (kind in ('model','macro','auto')),
  created_at      timestamptz not null default now()
);

-- Templates Meta (HSM)
create table wa_templates (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  channel_id      uuid references channels (id) on delete cascade,
  name            text not null,
  language        text not null default 'pt_BR',
  category        text,
  status          text default 'pending',
  components      jsonb not null default '[]',
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Automações (fluxos de chatbot) e campanhas
-- ---------------------------------------------------------------------
create table automations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  channel_id      uuid references channels (id) on delete set null,
  name            text not null,
  trigger         text,
  flow            jsonb not null default '{"nodes":[],"edges":[]}',
  active          boolean not null default false,
  updated_at      timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
create table campaigns (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  automation_id   uuid references automations (id) on delete set null,
  name            text not null,
  status          text not null default 'draft'
                    check (status in ('draft','scheduled','running','paused','done','failed')),
  audience        jsonb not null default '[]',
  scheduled_at    timestamptz,
  progress        int not null default 0,
  stats           jsonb not null default '{}',
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Planos de serviço (do provedor), API keys, integrações, IA, logs
-- ---------------------------------------------------------------------
create table plans (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  price           numeric(12,2),
  description     text,
  created_at      timestamptz not null default now()
);
create table api_keys (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  key_hash        text not null,
  scopes          text[] not null default '{}',
  last_used_at    timestamptz,
  created_at      timestamptz not null default now()
);
create table integrations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  type            text not null,           -- ex: 'sgp'
  config          jsonb not null default '{}',
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);
create table ai_agents (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  channel_id      uuid references channels (id) on delete set null,
  name            text not null,
  prompt          text,
  model           text default 'claude-sonnet-4-6',
  config          jsonb not null default '{}',
  active          boolean not null default false,
  created_at      timestamptz not null default now()
);
create table audit_logs (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  user_id         uuid references profiles (id) on delete set null,
  action          text not null,
  entity          text,
  metadata        jsonb not null default '{}',
  created_at      timestamptz not null default now()
);

-- ===== 0002_rls.sql =====
-- =====================================================================
-- RLS + onboarding
-- =====================================================================

-- Cria automaticamente um profile quando um usuário se cadastra no Auth.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Onboarding: cria a organização e vincula o usuário atual como admin.
create or replace function create_organization(org_name text, org_document text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org uuid;
begin
  if (select organization_id from profiles where id = auth.uid()) is not null then
    raise exception 'Usuário já pertence a uma organização';
  end if;

  insert into organizations (name, document) values (org_name, org_document)
  returning id into new_org;

  update profiles
     set organization_id = new_org, role = 'admin'
   where id = auth.uid();

  return new_org;
end;
$$;

-- ---------------------------------------------------------------------
-- Habilita RLS e aplica políticas por organização.
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  org_tables text[] := array[
    'organizations','profiles','departments','channels','contacts','conversations',
    'messages','tags','quick_replies','wa_templates','automations','campaigns',
    'plans','api_keys','integrations','ai_agents','audit_logs'
  ];
begin
  foreach t in array org_tables loop
    execute format('alter table %I enable row level security;', t);
  end loop;
end $$;

-- organizations: o usuário enxerga/edita a própria org.
create policy org_select on organizations for select using (id = current_org_id());
create policy org_update on organizations for update using (id = current_org_id() and current_role_is('admin'));

-- profiles: enxerga colegas da mesma org; edita o próprio (admin edita todos).
create policy profiles_select on profiles for select
  using (organization_id = current_org_id() or id = auth.uid());
create policy profiles_insert on profiles for insert
  with check (id = auth.uid());
create policy profiles_update on profiles for update
  using (id = auth.uid() or (organization_id = current_org_id() and current_role_is('admin')));

-- Demais tabelas: tudo restrito à org do usuário.
do $$
declare
  t text;
  scoped text[] := array[
    'departments','channels','contacts','conversations','messages','tags',
    'quick_replies','wa_templates','automations','campaigns','plans',
    'api_keys','integrations','ai_agents','audit_logs'
  ];
begin
  foreach t in array scoped loop
    execute format($f$
      create policy %1$s_all on %1$I
        for all
        using (organization_id = current_org_id())
        with check (organization_id = current_org_id());
    $f$, t);
  end loop;
end $$;

-- Tabelas de junção: herdam a org pela entidade pai.
alter table conversation_tags enable row level security;
alter table contact_tags enable row level security;

create policy conversation_tags_all on conversation_tags for all
  using (exists (select 1 from conversations c
                  where c.id = conversation_id and c.organization_id = current_org_id()))
  with check (exists (select 1 from conversations c
                  where c.id = conversation_id and c.organization_id = current_org_id()));

create policy contact_tags_all on contact_tags for all
  using (exists (select 1 from contacts c
                  where c.id = contact_id and c.organization_id = current_org_id()))
  with check (exists (select 1 from contacts c
                  where c.id = contact_id and c.organization_id = current_org_id()));

-- ===== 0003_realtime.sql =====
-- Habilita Realtime (broadcast de mudanças) para o chat ao vivo e o board Kanban.
alter publication supabase_realtime add table messages;
alter publication supabase_realtime add table conversations;

-- ===== 0004_views.sql =====
-- View para a inbox de atendimento: junta conversa + contato + canal + última mensagem.
-- security_invoker = true faz a view respeitar a RLS das tabelas para o usuário que consulta.
create view conversation_overview
with (security_invoker = true)
as
select
  c.id,
  c.organization_id,
  c.status,
  c.assigned_user_id,
  c.department_id,
  c.channel_id,
  c.contact_id,
  c.protocol,
  c.last_message_at,
  c.opened_at,
  c.closed_at,
  c.created_at,
  ct.name        as contact_name,
  ct.phone       as contact_phone,
  ct.avatar_url  as contact_avatar,
  ch.name        as channel_name,
  ch.type        as channel_type,
  lm.body         as last_message_body,
  lm.content_type as last_message_type,
  lm.direction    as last_message_direction
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join lateral (
  select body, content_type, direction
  from messages m
  where m.conversation_id = c.id
  order by m.created_at desc
  limit 1
) lm on true;

-- ===== 0005_avatars_bucket.sql =====
-- Bucket público para fotos de perfil dos contatos (sincronizadas da UAZAPI).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Leitura pública das imagens do bucket avatars.
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'avatars_public_read'
  ) then
    create policy "avatars_public_read" on storage.objects
      for select using (bucket_id = 'avatars');
  end if;
end $$;

-- ===== 0006_groups_mute.sql =====
-- Suporte a conversas de GRUPO e a silenciar (mute) conversas.
alter table contacts add column if not exists is_group boolean not null default false;
alter table conversations add column if not exists is_muted boolean not null default false;
alter table messages add column if not exists author_name text; -- quem enviou (participante do grupo)

-- Recria a view da inbox expondo is_group, is_muted e o autor da última mensagem.
drop view if exists conversation_overview;
create view conversation_overview
with (security_invoker = true)
as
select
  c.id,
  c.organization_id,
  c.status,
  c.assigned_user_id,
  c.department_id,
  c.channel_id,
  c.contact_id,
  c.protocol,
  c.last_message_at,
  c.opened_at,
  c.closed_at,
  c.created_at,
  c.is_muted,
  ct.name        as contact_name,
  ct.phone       as contact_phone,
  ct.avatar_url  as contact_avatar,
  ct.is_group    as is_group,
  ch.name        as channel_name,
  ch.type        as channel_type,
  lm.body         as last_message_body,
  lm.content_type as last_message_type,
  lm.direction    as last_message_direction,
  lm.author_name  as last_message_author
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join lateral (
  select body, content_type, direction, author_name
  from messages m
  where m.conversation_id = c.id
  order by m.created_at desc
  limit 1
) lm on true;

-- ===== 0007_media_bucket.sql =====
-- Bucket público para mídia das conversas (recebida e enviada).
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

-- Leitura pública dos arquivos de mídia.
do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'media_public_read'
  ) then
    create policy "media_public_read" on storage.objects
      for select using (bucket_id = 'media');
  end if;
end $$;

-- ===== 0008_message_interactions.sql =====
-- Interações de mensagem: responder (quote), reações, editar, apagar.
alter table messages add column if not exists reply_to_external text;   -- id externo da msg citada
alter table messages add column if not exists reply_excerpt text;        -- trecho da msg citada (cache)
alter table messages add column if not exists reply_author text;         -- autor da msg citada
alter table messages add column if not exists reactions jsonb not null default '[]'; -- [{emoji, by}]
alter table messages add column if not exists is_deleted boolean not null default false;
alter table messages add column if not exists edited boolean not null default false;

create index if not exists messages_external_id_idx on messages (external_id);

-- ===== 0009_bot_state.sql =====
-- Estado do chatbot por conversa (qual automação e em que nó parou aguardando resposta).
alter table conversations add column if not exists bot_automation_id uuid references automations (id) on delete set null;
alter table conversations add column if not exists bot_node_id text;

-- ===== 0010_author_phone.sql =====
-- Telefone real do autor de mensagens de grupo (para abrir conversa 1:1 ao clicar no nome).
alter table messages add column if not exists author_phone text;

-- ===== 0011_group_jid_lid.sql =====
-- JID completo do grupo (preserva traço de jids antigos) e LID do autor (p/ resolver 1:1).
alter table contacts add column if not exists chat_jid text;
alter table messages add column if not exists author_lid text;

-- Recria a view expondo o JID do contato/grupo.
drop view if exists conversation_overview;
create view conversation_overview
with (security_invoker = true)
as
select
  c.id, c.organization_id, c.status, c.assigned_user_id, c.department_id,
  c.channel_id, c.contact_id, c.protocol, c.last_message_at, c.opened_at,
  c.closed_at, c.created_at, c.is_muted,
  ct.name as contact_name, ct.phone as contact_phone, ct.avatar_url as contact_avatar,
  ct.is_group as is_group, ct.chat_jid as contact_jid,
  ch.name as channel_name, ch.type as channel_type,
  lm.body as last_message_body, lm.content_type as last_message_type,
  lm.direction as last_message_direction, lm.author_name as last_message_author
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join lateral (
  select body, content_type, direction, author_name
  from messages m where m.conversation_id = c.id
  order by m.created_at desc limit 1
) lm on true;

-- ===== 0012_avatar_src.sql =====
-- Impressão digital da foto-fonte (caminho da URL do WhatsApp, sem query de expiração).
-- Quando muda, sabemos que a pessoa trocou a foto e re-hospedamos a nova.
alter table contacts add column if not exists avatar_src text;

-- ===== 0013_protocol_close.sql =====
-- =====================================================================
-- Fase 1 — Protocolo de atendimento, encerramento e notas internas
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Protocolo: contador diário por organização + trigger de atribuição.
--    Formato: AAAAMMDD + sequência diária (4 dígitos). Ex.: 202606040001
-- ---------------------------------------------------------------------
create table if not exists protocol_counters (
  organization_id uuid not null references organizations (id) on delete cascade,
  day             date not null,
  seq             int  not null default 0,
  primary key (organization_id, day)
);

create or replace function assign_protocol()
returns trigger
language plpgsql
as $$
declare
  n     int;
  today date := (now() at time zone 'America/Bahia')::date;
begin
  if new.protocol is null or new.protocol = '' then
    insert into protocol_counters (organization_id, day, seq)
      values (new.organization_id, today, 1)
      on conflict (organization_id, day)
        do update set seq = protocol_counters.seq + 1
      returning seq into n;
    new.protocol := to_char(today, 'YYYYMMDD') || lpad(n::text, 4, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_assign_protocol on conversations;
create trigger trg_assign_protocol
  before insert on conversations
  for each row execute function assign_protocol();

-- Backfill: numera conversas existentes sem protocolo (por org+dia, ordem de criação).
with numbered as (
  select
    id,
    to_char((created_at at time zone 'America/Bahia')::date, 'YYYYMMDD') as ymd,
    row_number() over (
      partition by organization_id, (created_at at time zone 'America/Bahia')::date
      order by created_at
    ) as rn
  from conversations
  where protocol is null or protocol = ''
)
update conversations c
   set protocol = n.ymd || lpad(n.rn::text, 4, '0')
  from numbered n
 where n.id = c.id;

-- Sincroniza o contador com o que já existe (evita colisão com novos do mesmo dia).
insert into protocol_counters (organization_id, day, seq)
  select organization_id, (created_at at time zone 'America/Bahia')::date, count(*)
    from conversations
   group by 1, 2
  on conflict (organization_id, day)
    do update set seq = greatest(protocol_counters.seq, excluded.seq);

-- ---------------------------------------------------------------------
-- 2) Encerramento: motivo de encerramento (classificação via conversation_tags).
-- ---------------------------------------------------------------------
alter table conversations add column if not exists close_reason text;
-- Aguardando resposta da pesquisa de satisfação (captura a nota na próxima resposta do cliente).
alter table conversations add column if not exists awaiting_satisfaction boolean not null default false;

-- ---------------------------------------------------------------------
-- 3) Notas internas: mensagens visíveis só aos atendentes (não vão ao cliente).
-- ---------------------------------------------------------------------
alter table messages add column if not exists is_internal boolean not null default false;

-- ---------------------------------------------------------------------
-- 4) Recria a view da inbox expondo satisfação, motivo, atendente e depto.
-- ---------------------------------------------------------------------
drop view if exists conversation_overview;
create view conversation_overview
with (security_invoker = true)
as
select
  c.id, c.organization_id, c.status, c.assigned_user_id, c.department_id,
  c.channel_id, c.contact_id, c.protocol, c.last_message_at, c.opened_at,
  c.closed_at, c.created_at, c.is_muted, c.satisfaction, c.close_reason,
  c.bot_automation_id,
  ct.name as contact_name, ct.phone as contact_phone, ct.avatar_url as contact_avatar,
  ct.is_group as is_group, ct.chat_jid as contact_jid,
  ch.name as channel_name, ch.type as channel_type,
  pr.name as assigned_name,
  dp.name as department_name, dp.color as department_color,
  lm.body as last_message_body, lm.content_type as last_message_type,
  lm.direction as last_message_direction, lm.author_name as last_message_author,
  coalesce(ur.cnt, 0)::int as unread_count
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join profiles pr on pr.id = c.assigned_user_id
left join departments dp on dp.id = c.department_id
left join lateral (
  select body, content_type, direction, author_name
  from messages m
  where m.conversation_id = c.id and coalesce(m.is_internal, false) = false
  order by m.created_at desc
  limit 1
) lm on true
left join lateral (
  select count(*) as cnt
  from messages m2
  where m2.conversation_id = c.id and m2.direction = 'in' and m2.status <> 'read'
) ur on true;

-- ===== 0014_full_parity.sql =====
-- =====================================================================
-- 0014 — Paridade total com Chatmix: todas as tabelas/colunas faltantes
-- =====================================================================

-- =========================== CSAT (Pesquisa de Satisfação) ===========================
create table if not exists satisfaction_surveys (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  name            text not null,
  active          boolean not null default false,
  scale_type      text not null default 'stars' check (scale_type in ('stars','buttons')),
  scale_max       int not null default 5,
  question        text not null default 'De 1 a 5, como você avalia o nosso atendimento?',
  channels        uuid[] not null default '{}',   -- vazio = todos
  close_after_min int not null default 30,        -- encerra se cliente não responder
  created_at      timestamptz not null default now()
);

-- =========================== HORÁRIO DE ATENDIMENTO ===========================
create table if not exists business_hours (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  department_id   uuid references departments (id) on delete cascade, -- null = global da org
  day_of_week     int not null check (day_of_week between 0 and 6),   -- 0=domingo
  start_time      time not null default '08:00',
  end_time        time not null default '18:00',
  active          boolean not null default true,
  unique (organization_id, department_id, day_of_week)
);

-- =========================== MENSAGENS AUTOMÁTICAS POR EVENTO ===========================
create table if not exists auto_messages (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  event           text not null check (event in (
    'welcome','away','out_of_hours','close','queue_wait','agent_assign'
  )),
  channel_id      uuid references channels (id) on delete cascade, -- null = todos
  department_id   uuid references departments (id) on delete cascade, -- null = todos
  body            text not null,
  active          boolean not null default true,
  interval_min    int,  -- para queue_wait: reenvia a cada N min
  created_at      timestamptz not null default now()
);

-- =========================== CONFIGURAÇÕES DA ORGANIZAÇÃO ===========================
-- Expansão: organizations.settings JSONB já existe; vamos usá-lo com chaves bem-definidas.
-- Nada a criar em schema; os defaults ficam no código.

-- =========================== RECORRÊNCIA DE ATENDIMENTO ===========================
-- Campo na conversa para exibir badge Baixa/Média/Alta
-- (calculado on-the-fly; configuração em organizations.settings)

-- =========================== COLUNAS ADICIONAIS ===========================

-- Conversations: survey_id (qual pesquisa foi enviada)
alter table conversations add column if not exists survey_id uuid references satisfaction_surveys (id) on delete set null;

-- Conversations: closed_by (quem encerrou)
alter table conversations add column if not exists closed_by uuid references profiles (id) on delete set null;

-- Messages: forwarded (encaminhada)
alter table messages add column if not exists forwarded boolean not null default false;

-- Conversations: pinned (fixada)
alter table conversations add column if not exists pinned boolean not null default false;

-- Conversations: archived
alter table conversations add column if not exists archived boolean not null default false;

-- Contacts: campos CRM extras
alter table contacts add column if not exists email text;
alter table contacts add column if not exists birthday date;
alter table contacts add column if not exists city text;
alter table contacts add column if not exists address text;

-- Profiles: 2FA
alter table profiles add column if not exists totp_secret text;
alter table profiles add column if not exists totp_enabled boolean not null default false;

-- Profiles: avatar (foto de perfil do atendente)
-- já existe avatar_url

-- API keys: canal amarrado
alter table api_keys add column if not exists channel_id uuid references channels (id) on delete set null;

-- Campaigns: campos de disparo real
alter table campaigns add column if not exists channel_id uuid references channels (id) on delete set null;
alter table campaigns add column if not exists contact_filter jsonb not null default '{}';
alter table campaigns add column if not exists started_at timestamptz;
alter table campaigns add column if not exists finished_at timestamptz;
alter table campaigns add column if not exists total_contacts int not null default 0;
alter table campaigns add column if not exists sent_count int not null default 0;
alter table campaigns add column if not exists failed_count int not null default 0;

-- =========================== RLS nas tabelas novas ===========================
alter table satisfaction_surveys enable row level security;
create policy "org_surveys" on satisfaction_surveys using (organization_id = current_org_id());

alter table business_hours enable row level security;
create policy "org_hours" on business_hours using (organization_id = current_org_id());

alter table auto_messages enable row level security;
create policy "org_auto_msgs" on auto_messages using (organization_id = current_org_id());

-- =========================== VIEW ATUALIZADA ===========================
drop view if exists conversation_overview;
create view conversation_overview
with (security_invoker = true)
as
select
  c.id, c.organization_id, c.status, c.assigned_user_id, c.department_id,
  c.channel_id, c.contact_id, c.protocol, c.last_message_at, c.opened_at,
  c.closed_at, c.created_at, c.is_muted, c.satisfaction, c.close_reason,
  c.bot_automation_id, c.survey_id, c.pinned, c.archived,
  c.awaiting_satisfaction, c.closed_by,
  ct.name as contact_name, ct.phone as contact_phone, ct.avatar_url as contact_avatar,
  ct.is_group as is_group, ct.chat_jid as contact_jid,
  ct.email as contact_email, ct.city as contact_city,
  ch.name as channel_name, ch.type as channel_type,
  pr.name as assigned_name,
  dp.name as department_name, dp.color as department_color,
  lm.body as last_message_body, lm.content_type as last_message_type,
  lm.direction as last_message_direction, lm.author_name as last_message_author,
  lm.created_at as last_message_created_at,
  coalesce(ur.cnt, 0)::int as unread_count
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join profiles pr on pr.id = c.assigned_user_id
left join departments dp on dp.id = c.department_id
left join lateral (
  select body, content_type, direction, author_name, created_at
  from messages m
  where m.conversation_id = c.id and coalesce(m.is_internal, false) = false
  order by m.created_at desc
  limit 1
) lm on true
left join lateral (
  select count(*) as cnt
  from messages m2
  where m2.conversation_id = c.id and m2.direction = 'in' and m2.status <> 'read'
) ur on true;

-- =========================== REALTIME nas tabelas novas ===========================
alter publication supabase_realtime add table satisfaction_surveys;
alter publication supabase_realtime add table auto_messages;

-- ===== 0015_conversation_ai.sql =====
-- =====================================================================
-- 0015 — Controle por conversa do atendimento por IA (pausar/reativar)
-- Equivalente ao "assumir / devolver para a automação" + block_return_to_bot
-- do Chatmix, mas no nível da conversa.
-- =====================================================================

-- true (padrão) = a IA pode atuar nesta conversa.
-- false = atendente pausou a IA; o chatbot NÃO reengaja, mesmo em conversa nova.
alter table conversations add column if not exists ai_enabled boolean not null default true;

-- Recria a view expondo ai_enabled. MANTÉM unread_count (não remover!).
drop view if exists conversation_overview;
create view conversation_overview
with (security_invoker = true)
as
select
  c.id, c.organization_id, c.status, c.assigned_user_id, c.department_id,
  c.channel_id, c.contact_id, c.protocol, c.last_message_at, c.opened_at,
  c.closed_at, c.created_at, c.is_muted, c.satisfaction, c.close_reason,
  c.bot_automation_id, c.survey_id, c.pinned, c.archived,
  c.awaiting_satisfaction, c.closed_by, c.ai_enabled,
  ct.name as contact_name, ct.phone as contact_phone, ct.avatar_url as contact_avatar,
  ct.is_group as is_group, ct.chat_jid as contact_jid,
  ct.email as contact_email, ct.city as contact_city,
  ch.name as channel_name, ch.type as channel_type,
  pr.name as assigned_name,
  dp.name as department_name, dp.color as department_color,
  lm.body as last_message_body, lm.content_type as last_message_type,
  lm.direction as last_message_direction, lm.author_name as last_message_author,
  lm.created_at as last_message_created_at,
  coalesce(ur.cnt, 0)::int as unread_count
from conversations c
join contacts ct on ct.id = c.contact_id
join channels ch on ch.id = c.channel_id
left join profiles pr on pr.id = c.assigned_user_id
left join departments dp on dp.id = c.department_id
left join lateral (
  select body, content_type, direction, author_name, created_at
  from messages m
  where m.conversation_id = c.id and coalesce(m.is_internal, false) = false
  order by m.created_at desc
  limit 1
) lm on true
left join lateral (
  select count(*) as cnt
  from messages m2
  where m2.conversation_id = c.id and m2.direction = 'in' and m2.status <> 'read'
) ur on true;

-- ===== 0016_ai_allowlist.sql =====
-- Allowlist de números autorizados a receber atendimento por IA.
-- Rollout controlado: quando o agente está com restrict_to_allowlist=true,
-- só os números desta lista (active) recebem resposta da IA; os demais vão
-- direto para a fila humana.

create table if not exists ai_allowed_numbers (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id) on delete cascade,
  phone           text not null,                 -- só dígitos (ex.: 5573999998888)
  label           text,                          -- nome/observação
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  unique (organization_id, phone)
);

create index if not exists ai_allowed_numbers_org_phone_idx
  on ai_allowed_numbers (organization_id, phone);

alter table ai_allowed_numbers enable row level security;

-- Acesso restrito à própria organização (mesma convenção das demais tabelas: current_org_id()).
drop policy if exists ai_allowed_numbers_all on ai_allowed_numbers;
create policy ai_allowed_numbers_all on ai_allowed_numbers for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

-- ===== 0017_automation_integration_schedule.sql =====
-- Vincula cada automação a uma integração SGP específica (opcional).
-- Quando preenchido, o pipeline usa esse SGP em vez de buscar o primeiro da org.
alter table automations
  add column if not exists integration_id uuid references integrations(id) on delete set null;

-- Horário de execução por automação.
-- Formato: {"sun":[],"mon":[["08:00","18:00"]],...}
-- null ou objeto vazio = sem restrição (roda 24/7).
alter table automations
  add column if not exists schedule jsonb;

-- ===== 0018_campaign_message.sql =====
-- Texto de disparo da campanha (usado quando não há fluxo, ou como override
-- da 1ª mensagem do fluxo de automação vinculado).
alter table campaigns
  add column if not exists message text;

-- ===== 0020_conversation_variables.sql =====
-- Variáveis coletadas durante o fluxo de automação (nós "input") e merge fields.
alter table conversations
  add column if not exists variables jsonb not null default '{}'::jsonb;

-- ===== 0021_super_admin.sql =====
-- Marca de superadmin (acesso ao painel /superadmin).
alter table public.profiles
  add column if not exists super_admin boolean not null default false;

-- ===== 0022_internal_messages_mentions.sql =====
-- Mensagens internas entre atendentes: menções + notificações (sino).

-- Menções em mensagens internas: array de { id, name } dos atendentes marcados.
alter table public.messages
  add column if not exists mentions jsonb not null default '[]'::jsonb;

-- Notificações de menção interna (para o sino/badge por atendente).
create table if not exists public.internal_mentions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  mentioned_user_id uuid not null,
  created_by uuid,
  author_name text,
  excerpt text,
  contact_name text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_internal_mentions_user
  on public.internal_mentions(mentioned_user_id, read_at);
create index if not exists idx_internal_mentions_conv
  on public.internal_mentions(conversation_id);

alter table public.internal_mentions enable row level security;

-- Cada atendente vê e marca como lida apenas as próprias menções.
drop policy if exists internal_mentions_select on public.internal_mentions;
create policy internal_mentions_select on public.internal_mentions
  for select using (mentioned_user_id = auth.uid());

drop policy if exists internal_mentions_update on public.internal_mentions;
create policy internal_mentions_update on public.internal_mentions
  for update using (mentioned_user_id = auth.uid());

-- Realtime para o sino.
alter publication supabase_realtime add table public.internal_mentions;

-- ===== 0023_app_logs.sql =====
-- Logs de aplicação acessíveis fora do Easypanel (lidos no /superadmin e via REST).
create table if not exists public.app_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  level text not null default 'info',          -- info | warn | error
  source text not null default 'app',          -- webhook | chatbot | ai | sgp | send | ...
  message text not null,
  meta jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_app_logs_created on public.app_logs(created_at desc);
create index if not exists idx_app_logs_level on public.app_logs(level, created_at desc);

alter table public.app_logs enable row level security;
-- Sem policies: só o service role (servidor) escreve/lê.

-- ===== 0024_inactivity_auto_close.sql =====
-- Encerramento por inatividade: marca quando o aviso foi enviado (pra não repetir).
alter table public.conversations
  add column if not exists inactivity_warned_at timestamptz;

-- Índice pra o cron achar conversas ociosas de forma barata.
create index if not exists idx_conversations_org_status_lastmsg
  on public.conversations(organization_id, status, last_message_at);

-- ===== 0025_message_deleted_scope.sql =====
-- Escopo da exclusão: 'me' (só na plataforma) ou 'everyone' (revogada no cliente).
-- A mensagem permanece no banco (faded na UI) para auditoria/admin.
alter table public.messages
  add column if not exists deleted_scope text;

-- ===== 0026_essentiale.sql =====
-- ─────────────────────────────────────────────────────────────────────────────
-- 0021 — Domínio Essentiale: catálogo, fragrâncias, pedidos, follow-ups, LGPD
-- Depende de: 0001 (organizations, contacts, conversations), 0002 (current_org_id()).
-- Idempotente: pode rodar mais de uma vez sem erro.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Catálogo de produtos ────────────────────────────────────────────────────
create table if not exists products (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  nome             text not null,
  slug             text not null,
  categoria        text not null,
  preco_centavos   integer not null default 0,
  url_produto      text,
  descricao        text,
  caracteristicas  jsonb not null default '[]',
  exemplos_de_uso  jsonb not null default '[]',
  cuidados         text,
  fragrancia       text,
  foto_arquivo     text,
  foto_url         text,
  galeria          jsonb not null default '[]',
  ativo            boolean not null default true,
  estoque          integer not null default 999,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_products_org on products (organization_id);
create index if not exists idx_products_categoria on products (organization_id, categoria);
create unique index if not exists uq_products_org_slug on products (organization_id, slug);

-- ── Fragrâncias ─────────────────────────────────────────────────────────────
create table if not exists fragrances (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  nome             text not null,
  perfil           text,
  indicar_para     text,
  notas            jsonb not null default '{}',
  confirmada       boolean not null default false,
  created_at       timestamptz not null default now()
);
create index if not exists idx_fragrances_org on fragrances (organization_id);
create unique index if not exists uq_fragrances_org_nome on fragrances (organization_id, nome);

-- ── Pedidos ─────────────────────────────────────────────────────────────────
create table if not exists orders (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references organizations (id) on delete cascade,
  conversation_id    uuid references conversations (id) on delete set null,
  contact_id         uuid references contacts (id) on delete set null,
  nome_completo      text,
  cpf                text,
  email              text,
  telefone           text,
  endereco           text,
  cep                text,
  tipo_entrega       text default 'entrega',
  quem_recebe        text,
  subtotal_centavos  integer not null default 0,
  frete_centavos     integer not null default 0,
  desconto_centavos  integer not null default 0,
  total_centavos     integer not null default 0,
  payment_method     text default 'pix',
  payment_status     text default 'pending',
  checkout_url       text,
  pix_code           text,
  status             text not null default 'novo',
  tracking_code      text,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists idx_orders_org on orders (organization_id, created_at desc);
create index if not exists idx_orders_status on orders (organization_id, status);

-- ── Itens do pedido ─────────────────────────────────────────────────────────
create table if not exists order_items (
  id                       uuid primary key default gen_random_uuid(),
  order_id                 uuid not null references orders (id) on delete cascade,
  product_id               uuid references products (id) on delete set null,
  nome                     text not null,
  fragrancia               text,
  quantidade               integer not null default 1,
  preco_unitario_centavos  integer not null default 0,
  subtotal_centavos        integer not null default 0,
  personalizacao           text,
  created_at               timestamptz not null default now()
);
create index if not exists idx_order_items_order on order_items (order_id);

-- ── Follow-ups (réguas de relacionamento / pós-venda) ───────────────────────
create table if not exists followups (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  contact_id       uuid references contacts (id) on delete set null,
  conversation_id  uuid references conversations (id) on delete set null,
  order_id         uuid references orders (id) on delete set null,
  tipo             text not null,
  status           text not null default 'pendente',
  scheduled_at     timestamptz,
  sent_at          timestamptz,
  message_body     text,
  created_at       timestamptz not null default now()
);
create index if not exists idx_followups_due on followups (organization_id, status, scheduled_at);

-- ── Registro de consentimento (LGPD) ────────────────────────────────────────
create table if not exists consent_log (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  contact_id       uuid references contacts (id) on delete set null,
  tipo             text not null,
  canal            text,
  mensagem_ref     text,
  ip               text,
  created_at       timestamptz not null default now()
);
create index if not exists idx_consent_contact on consent_log (organization_id, contact_id);

-- ── Colunas de CRM em contacts (Guia §8.4) ──────────────────────────────────
alter table contacts add column if not exists birthday               date;
alter table contacts add column if not exists city                   text;
alter table contacts add column if not exists address                text;
alter table contacts add column if not exists data_aniversario       date;
alter table contacts add column if not exists origem_lead            text;
alter table contacts add column if not exists tipo_cliente           text;
alter table contacts add column if not exists status_funil           text;
alter table contacts add column if not exists consentimento_marketing boolean default false;
alter table contacts add column if not exists interesses             jsonb default '[]';
alter table contacts add column if not exists cpf                    text;
alter table contacts add column if not exists historico_pedidos      jsonb default '[]';

-- ── RLS: cada org só enxerga os próprios registros (current_org_id()) ───────
alter table products    enable row level security;
alter table fragrances  enable row level security;
alter table orders      enable row level security;
alter table order_items enable row level security;
alter table followups   enable row level security;
alter table consent_log enable row level security;

drop policy if exists products_all on products;
create policy products_all on products for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

drop policy if exists fragrances_all on fragrances;
create policy fragrances_all on fragrances for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

drop policy if exists orders_all on orders;
create policy orders_all on orders for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

drop policy if exists order_items_all on order_items;
create policy order_items_all on order_items for all
  using (exists (select 1 from orders o where o.id = order_items.order_id and o.organization_id = current_org_id()));

drop policy if exists followups_all on followups;
create policy followups_all on followups for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

drop policy if exists consent_all on consent_log;
create policy consent_all on consent_log for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

-- ===== 0027_grants.sql =====
-- ─────────────────────────────────────────────────────────────────────────────
-- GRANTs para os roles do Supabase (anon, authenticated, service_role).
-- O Supabase normalmente aplica isso automaticamente, mas quando o schema é
-- provisionado via SQL cru (Management API / SQL Editor), os grants podem faltar
-- e tudo dá "permission denied" mesmo com RLS correto. A segurança continua por
-- conta do RLS (já habilitado nas tabelas) — o grant só permite o role TENTAR.
-- Rodar por último, depois de todas as tabelas criadas. Idempotente.
-- ─────────────────────────────────────────────────────────────────────────────
grant usage on schema public to anon, authenticated, service_role;

grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all functions in schema public to anon, authenticated, service_role;

-- Tabelas/sequências/funções criadas no futuro herdam os mesmos grants.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

-- ===== 0028_postsale.sql =====
-- ─────────────────────────────────────────────────────────────────────────────
-- 0028 — Pós-venda automático (Guia §12: status de pedido + réguas de relacionamento)
-- Depende de: 0026_essentiale.sql (tabela followups, colunas em contacts).
-- Idempotente: pode rodar mais de uma vez sem erro.
--
-- Nenhuma coluna nova é necessária: `followups.status` é TEXT, então os novos
-- valores usados pelo código ('enviado', 'aguardando_template') já cabem sem
-- alteração de schema. Esta migração apenas garante a existência da tabela e
-- adiciona índices que aceleram as consultas do cron de pós-venda.
-- ─────────────────────────────────────────────────────────────────────────────

-- Garante a tabela followups (no-op se 0026 já a criou).
create table if not exists followups (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  contact_id       uuid references contacts (id) on delete set null,
  conversation_id  uuid references conversations (id) on delete set null,
  order_id         uuid references orders (id) on delete set null,
  tipo             text not null,
  status           text not null default 'pendente',
  scheduled_at     timestamptz,
  sent_at          timestamptz,
  message_body     text,
  created_at       timestamptz not null default now()
);

-- Índice principal usado por processDueFollowups (status + scheduled_at).
create index if not exists idx_followups_due on followups (organization_id, status, scheduled_at);

-- Evita reprocessar/duplicar réguas: lookups por (order_id, tipo) e (contact_id, tipo).
create index if not exists idx_followups_order_tipo on followups (organization_id, order_id, tipo);
create index if not exists idx_followups_contact_tipo on followups (organization_id, contact_id, tipo);

-- Acelera a régua de aniversário (varredura de contacts.data_aniversario).
create index if not exists idx_contacts_aniversario on contacts (organization_id, data_aniversario)
  where data_aniversario is not null;

-- ===== 0029_campaigns.sql =====
-- ─────────────────────────────────────────────────────────────────────────────
-- 0029 — Campanhas e disparos (Essentiale, Guia §11)
-- Depende de: 0001 (campaigns, contacts, channels, conversations, messages),
--             0002 (current_org_id() + RLS genérica de campaigns),
--             0018 (campaigns.message), 0026 (contacts CRM: city, tipo_cliente,
--                   interesses, status_funil, consentimento_marketing).
-- Idempotente: pode rodar mais de uma vez sem erro.
-- NÃO EXECUTAR automaticamente — apenas versionar.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Colunas que o app já espera em `campaigns` (type Campaign) mas que a
--    tabela base (0001) não tinha. Tudo com `if not exists` p/ ser idempotente.
alter table campaigns add column if not exists channel_id     uuid references channels (id) on delete set null;
alter table campaigns add column if not exists contact_filter jsonb       not null default '{}';
alter table campaigns add column if not exists started_at      timestamptz;
alter table campaigns add column if not exists finished_at     timestamptz;
alter table campaigns add column if not exists total_contacts  integer     not null default 0;
alter table campaigns add column if not exists sent_count      integer     not null default 0;
alter table campaigns add column if not exists failed_count    integer     not null default 0;

-- A tabela base já restringe status a um CHECK fixo. Acrescentamos o estado
-- 'sending' (em disparo) sem quebrar os valores antigos, recriando o CHECK.
alter table campaigns drop constraint if exists campaigns_status_check;
alter table campaigns add  constraint campaigns_status_check
  check (status in ('draft','scheduled','running','sending','paused','done','failed'));

create index if not exists idx_campaigns_org_created on campaigns (organization_id, created_at desc);

-- ── Log de envios por destinatário (Guia §11.3 — status por contato) ─────────
-- Uma linha por (campanha, contato). Guarda o resultado individual do disparo,
-- a janela de 24h respeitada e a referência da mensagem no provedor.
create table if not exists campaign_recipients (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references organizations (id) on delete cascade,
  campaign_id      uuid not null references campaigns (id) on delete cascade,
  contact_id       uuid references contacts (id) on delete set null,
  phone            text,
  name             text,
  -- pending: na fila | sent: enviado (texto livre, janela 24h aberta)
  -- failed: erro no envio
  -- aguardando_template: disparo proativo fora da janela 24h → exige HSM aprovado
  -- skipped_opt_out: contato sem consentimento_marketing (não deveria ocorrer p/ filtro, mas registra)
  status           text not null default 'pending'
                     check (status in ('pending','sent','failed','aguardando_template','skipped_opt_out')),
  channel          text,                 -- type do canal (meta_cloud / uazapi)
  external_id      text,                 -- id da mensagem no provedor
  error            text,                 -- mensagem de erro quando status='failed'
  in_window_24h    boolean,              -- true se havia inbound do contato < 24h
  sent_at          timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists idx_campaign_recipients_campaign on campaign_recipients (campaign_id, status);
create index if not exists idx_campaign_recipients_org on campaign_recipients (organization_id);
create unique index if not exists uq_campaign_recipients_unique on campaign_recipients (campaign_id, contact_id);

-- ── RLS: cada org só enxerga os próprios destinatários ───────────────────────
alter table campaign_recipients enable row level security;
drop policy if exists campaign_recipients_all on campaign_recipients;
create policy campaign_recipients_all on campaign_recipients for all
  using (organization_id = current_org_id())
  with check (organization_id = current_org_id());

-- ===== 0030_contacts_updated_at.sql =====
-- ─────────────────────────────────────────────────────────────────────────────
-- contacts.updated_at — o código (registrar_cliente, registrar_optout, criar_pedido)
-- atualiza esta coluna ao enriquecer o CRM. Sem ela, esses updates falhavam em
-- silêncio (coluna inexistente) e o CRM do contato ficava vazio. Idempotente.
-- ─────────────────────────────────────────────────────────────────────────────
alter table contacts add column if not exists updated_at timestamptz not null default now();


-- ============================================================================
-- SEED ROYAL PRINT — organizacao, dados base, agente de IA e 5 logins
-- ============================================================================
set search_path = public, extensions;
create extension if not exists pgcrypto;

-- Cria os logins (auth.users + identities + profiles) de forma robusta.
create or replace function pg_temp.mk_login(p_user text, p_name text, p_role text, p_org uuid, p_pwd text)
returns uuid language plpgsql as $fn$
declare
  uid uuid := gen_random_uuid();
  mail text := lower(p_user) || '@royalprint.com.br';
  existing uuid;
begin
  select id into existing from auth.users where email = mail;
  if existing is not null then uid := existing; end if;

  if existing is null then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data, is_super_admin
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      mail, crypt(p_pwd, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('name', p_name), false
    );
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, mail,
      jsonb_build_object('sub', uid::text, 'email', mail), 'email',
      now(), now(), now()
    );
  end if;

  insert into profiles (id, organization_id, name, email, role)
  values (uid, p_org, p_name, mail, p_role)
  on conflict (id) do update
    set organization_id = excluded.organization_id, name = excluded.name, role = excluded.role;
  return uid;
end $fn$;

do $$
declare
  org uuid;
  pwd text := 'RoyalPrint@2026';
begin
  -- Organizacao unica
  select id into org from organizations order by created_at limit 1;
  if org is null then
    insert into organizations (name, document) values ('Royal Print', null) returning id into org;
  end if;

  update organizations set settings = coalesce(settings,'{}'::jsonb) || jsonb_build_object(
    'business_hours','{"mon_fri":"07:30-18:00","sat":"08:00-13:00","sun":"closed"}'::jsonb,
    'address','Av. Hist. Pereira Costa, 447 — Cabo de Santo Agostinho/PE',
    'inactivity_enabled', true, 'inactivity_warn_min', 10, 'inactivity_close_min', 15
  ) where id = org;

  -- Departamentos
  insert into departments (organization_id, name, color)
  select org, d.name, d.color from (values
    ('Assistência Técnica','#00a8ff'), ('Financeiro','#f59e0b'), ('Gráfica / Vendas','#10b981')
  ) as d(name,color)
  where not exists (select 1 from departments x where x.organization_id=org and x.name=d.name);

  -- Tags
  insert into tags (organization_id, name, color, scope)
  select org, t.name, t.color, t.scope from (values
    ('Aguardando orçamento','#f59e0b','conversation'),
    ('Aguardando pagamento','#ef4444','conversation'),
    ('OS aberta','#8b5cf6','conversation'),
    ('Resolvido','#10b981','conversation'),
    ('Cliente PJ','#0ea5e9','contact')
  ) as t(name,color,scope)
  where not exists (select 1 from tags x where x.organization_id=org and x.name=t.name and x.scope=t.scope);

  -- Respostas rapidas
  insert into quick_replies (organization_id, title, content, shortcut, kind)
  select org, q.title, q.content, q.shortcut, 'model' from (values
    ('Saudação','Olá! Bem-vindo(a) à Royal Print! 🖨️ Como posso te ajudar hoje?','/oi'),
    ('Horário','Atendemos de seg a sex, 7:30 às 18h, e sáb das 8h às 13h.','/horario'),
    ('Localização','Estamos na Av. Hist. Pereira Costa, 447 — Cabo de Santo Agostinho/PE.','/local'),
    ('Delivery','Temos Delivery 🏍️ para buscar e entregar seu equipamento. Quer agendar?','/delivery')
  ) as q(title,content,shortcut)
  where not exists (select 1 from quick_replies x where x.organization_id=org and x.title=q.title);

  -- Agente de IA padrao (Sofia)
  insert into ai_agents (organization_id, channel_id, name, prompt, model, config, active)
  select org, null, 'Sofia', '', 'gpt-4.1-mini',
    '{"temperature":0.3,"use_emojis":true,"single_message":false,"execute_actions":true,"restrict_to_allowlist":false,"tone":"Profissional, técnica e prestativa — Royal Print","greeting":"Olá! Bem-vindo(a) à Royal Print! 🖨️ Como posso te ajudar hoje?"}'::jsonb,
    true
  where not exists (select 1 from ai_agents where organization_id=org);

  -- Automacao padrao
  insert into automations (organization_id, name, flow, active)
  select org, 'Atendimento Royal Print',
    '{"nodes":[{"id":"start","data":{"kind":"start"}},{"id":"ai1","data":{"kind":"ai","content":"Continue o atendimento como atendente da Royal Print."}}],"edges":[{"id":"e1","source":"start","target":"ai1"}]}'::jsonb,
    true
  where not exists (select 1 from automations x where x.organization_id=org and x.name='Atendimento Royal Print');

  -- 5 LOGINS (usuario@royalprint.com.br) — senha: RoyalPrint@2026
  perform pg_temp.mk_login('adonias', 'Adonias Souza', 'admin', org, pwd);
  perform pg_temp.mk_login('paulo',   'Paulo Moshe',   'admin', org, pwd);
  perform pg_temp.mk_login('julio',   'Júlio Cesar',   'agent', org, pwd);
  perform pg_temp.mk_login('elani',   'Elani',         'agent', org, pwd);
  perform pg_temp.mk_login('mayara',  'Mayara',        'agent', org, pwd);
end $$;

-- Conferencia
select p.name, p.role, u.email
from profiles p join auth.users u on u.id = p.id
order by p.role desc, p.name;
