-- ───────────────────────────────────────────────────────────────────────────
-- Seed da Royal Print (single-tenant)
-- Aplique DEPOIS de:
--   1) registrar o admin em /cadastro
--   2) criar a organização "Royal Print" em /onboarding
-- Idempotente: usa NOT EXISTS para não duplicar em reexecuções.
-- Alvo: a organização única (a primeira criada). Ajuste o WHERE se necessário.
-- ───────────────────────────────────────────────────────────────────────────

do $$
declare
  org uuid := (select id from organizations order by created_at limit 1);
begin
  if org is null then
    raise exception 'Nenhuma organização encontrada. Crie a org Royal Print em /onboarding antes do seed.';
  end if;

  -- ── Configurações da org (horário, inatividade) ──
  update organizations
     set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object(
       'business_hours', '{"mon_fri":"07:30-18:00","sat":"08:00-13:00","sun":"closed"}'::jsonb,
       'address', 'Av. Hist. Pereira Costa, 447 — Cabo de Santo Agostinho/PE',
       'inactivity_enabled', true,
       'inactivity_warn_min', 10,
       'inactivity_close_min', 15
     )
   where id = org;

  -- ── Departamentos ──
  insert into departments (organization_id, name, color)
  select org, d.name, d.color
  from (values
    ('Assistência Técnica', '#00a8ff'),
    ('Financeiro',          '#f59e0b'),
    ('Gráfica / Vendas',    '#10b981')
  ) as d(name, color)
  where not exists (
    select 1 from departments x where x.organization_id = org and x.name = d.name
  );

  -- ── Tags ──
  insert into tags (organization_id, name, color, scope)
  select org, t.name, t.color, t.scope
  from (values
    ('Aguardando orçamento', '#f59e0b', 'conversation'),
    ('Aguardando pagamento', '#ef4444', 'conversation'),
    ('OS aberta',            '#8b5cf6', 'conversation'),
    ('Resolvido',            '#10b981', 'conversation'),
    ('Cliente PJ',           '#0ea5e9', 'contact')
  ) as t(name, color, scope)
  where not exists (
    select 1 from tags x where x.organization_id = org and x.name = t.name and x.scope = t.scope
  );

  -- ── Respostas rápidas ──
  insert into quick_replies (organization_id, title, content, shortcut, kind)
  select org, q.title, q.content, q.shortcut, 'model'
  from (values
    ('Saudação',    'Olá! Bem-vindo(a) à Royal Print! 🖨️ Como posso te ajudar hoje?', '/oi'),
    ('Horário',     'Atendemos de seg a sex, 7:30 às 18h, e sáb das 8h às 13h.',       '/horario'),
    ('Localização', 'Estamos na Av. Hist. Pereira Costa, 447 — Cabo de Santo Agostinho/PE.', '/local'),
    ('Delivery',    'Temos Delivery 🏍️ para buscar e entregar seu equipamento. Quer agendar?', '/delivery')
  ) as q(title, content, shortcut)
  where not exists (
    select 1 from quick_replies x where x.organization_id = org and x.title = q.title
  );

  -- ── Mapeia TODO usuário do Auth para a org como admin ──
  -- Sem isto, current_org_id() devolve NULL e o RLS bloqueia tudo.
  -- (O fluxo normal é /onboarding já linkar o admin; isto cobre usuários extras.)
  insert into profiles (id, organization_id, name, role)
  select u.id, org,
         coalesce(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1), 'Admin'),
         'admin'
  from auth.users u
  on conflict (id) do update
    set organization_id = excluded.organization_id;

  -- ── Agente de IA padrão (Sofia) ──
  -- prompt vazio = usa o prompt-base da Royal Print embutido no código (ai.ts).
  insert into ai_agents (organization_id, channel_id, name, prompt, model, config, active)
  select org, null, 'Sofia', '', 'gpt-4.1-mini',
    '{
      "temperature": 0.3,
      "use_emojis": true,
      "single_message": false,
      "execute_actions": true,
      "restrict_to_allowlist": false,
      "tone": "Profissional, técnica e prestativa — atendimento Royal Print",
      "greeting": "Olá! Bem-vindo(a) à Royal Print! 🖨️ Como posso te ajudar hoje?"
    }'::jsonb,
    true
  where not exists (select 1 from ai_agents where organization_id = org);

  -- ── Automação "Atendimento Royal Print": start → nó de IA ──
  insert into automations (organization_id, name, flow, active)
  select org, 'Atendimento Royal Print',
    $json$ {"nodes":[{"id":"start","data":{"kind":"start"}},{"id":"ai1","data":{"kind":"ai","content":"Continue o atendimento como atendente da Royal Print."}}],"edges":[{"id":"e1","source":"start","target":"ai1"}]} $json$::jsonb,
    true
  where not exists (
    select 1 from automations x where x.organization_id = org and x.name = 'Atendimento Royal Print'
  );
end $$;
