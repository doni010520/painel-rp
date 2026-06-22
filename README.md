# Royal Print — Atendimento WhatsApp

Plataforma de multiatendimento e automação via WhatsApp da **Royal Print**
(assistência técnica de impressoras/computadores + serviços gráficos — Cabo de
Santo Agostinho/PE). Single-tenant.

Stack: **Next.js 16 (App Router) + TypeScript + Tailwind v4 + Supabase**.
Integrações WhatsApp: **uazapi** (QR) e **Meta Cloud API** (oficial, opcional).

> Gestão de catálogo, pedidos e Ordens de Serviço fica no **VHSys** — esta
> aplicação foca no **atendimento** (inbox, canais, automações, campanhas, IA,
> relatórios).

## Rodar em desenvolvimento

```bash
npm install
npm run dev        # http://localhost:3000
```

Sem `.env.local`, o app sobe em **modo preview** (dados de exemplo, sem login).

## Conectar o Supabase (dados reais + login)

A Royal Print usa um **Supabase Cloud** (projeto `skacswwfbbdbtabgqsqy`).

1. Copie `.env.local.example` para `.env.local` e preencha:
   - `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
   - `UAZAPI_HOST` (`https://benitechlab.uazapi.com`), `UAZAPI_ADMIN_TOKEN`
2. Aplique as migrations de `supabase/migrations/` no SQL Editor, **na ordem**
   (`0001` → `0030`).
3. Reinicie `npm run dev`. Acesse `/cadastro` → crie a conta admin → em
   `/onboarding` crie a organização **"Royal Print"**.
4. Rode `supabase/seed_royalprint.sql` no SQL Editor (departamentos, tags,
   respostas rápidas, agente de IA "Sofia" e automação padrão).

## Webhooks (precisam de URL pública do VPS)

- uazapi: `POST  https://SEU-DOMINIO/api/webhooks/uazapi`
- Meta:   `GET/POST https://SEU-DOMINIO/api/webhooks/meta`

## Estrutura

```
src/app/(app)/*      telas autenticadas (dashboard, canais, atendimento, ...)
src/app/login        login / cadastro / onboarding
src/app/api/webhooks rotas de webhook (uazapi, meta)
src/lib/supabase     clientes (browser/server) + proxy de sessão
src/lib/whatsapp     adapters ChannelProvider (uazapi.ts, meta.ts) + inbound + IA
supabase/migrations  schema + RLS + realtime
supabase/seed_royalprint.sql  seed single-tenant da Royal Print
```

## Deploy (EasyPanel)

Use o `Dockerfile` da raiz (saída Next standalone). A app lê a config pública do
Supabase em **runtime** (o layout é `force-dynamic` e injeta `window.__SB_*`), então
**todas** as variáveis abaixo vão como **Environment Variables no EasyPanel** — não é
preciso embutir a anon key no build.

Variáveis de runtime no EasyPanel:

```
NEXT_PUBLIC_SUPABASE_URL=https://skacswwfbbdbtabgqsqy.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon public do projeto>
SUPABASE_SERVICE_ROLE_KEY=<service_role — SECRETA>
UAZAPI_HOST=https://benitechlab.uazapi.com
UAZAPI_ADMIN_TOKEN=<token>
APP_BASE_URL=https://<dominio-gerado>
CRON_SECRET=<aleatório>
# opcionais: OPENAI_API_KEY, SGP_ENCRYPTION_KEY, FINANCEIRO_WHATSAPP, ROYALPRINT_PIX_KEY
```

Depois aponte o webhook do uazapi para `https://<dominio-gerado>/api/webhooks/uazapi`.
