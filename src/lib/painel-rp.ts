/**
 * Config do "Painel RP" (Atendimentos/Tickets + Disparos) integrado do antigo
 * repo painel-rp. O backend continua sendo os webhooks do N8N (que falam com o
 * Supabase cloud) — aqui só centralizamos as URLs, configuráveis por env.
 */
const N8N_BASE = (
  process.env.N8N_BASE_URL || "https://benitech-n8n.x3t6qy.easypanel.host/webhook"
).replace(/\/$/, "");

export const PAINEL_RP = {
  /** Lista (GET) e atualiza (PATCH) tickets da tabela `atendimentos`. */
  painel: process.env.N8N_PAINEL_URL || `${N8N_BASE}/painel-rp`,
  /** Métricas de atendimento (GET). */
  metricas: process.env.N8N_METRICAS_URL || `${N8N_BASE}/painel-rp-metricas`,
  /** Disparos: listar/criar/cancelar/contatos (POST com {action}). */
  disparos: process.env.N8N_DISPAROS_URL || `${N8N_BASE}/disparos`,
  /** Bucket do Supabase Storage onde a mídia de disparo é enviada. */
  bucket: process.env.DISPAROS_BUCKET || "disparos",
};
