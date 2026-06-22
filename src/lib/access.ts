/**
 * Controle de acesso por papel (RBAC) — leve, sem imports de UI, para poder ser
 * usado também no middleware.
 *
 * Papéis: admin / supervisor → acesso total. agent (atendente) → só o operacional.
 */
export type Role = "admin" | "supervisor" | "agent";

/** Prefixos de rota liberados ao ATENDENTE (agent). Admin/supervisor veem tudo. */
export const AGENT_PREFIXES = [
  "/dashboard",
  "/atendimento",   // cobre /atendimento e /atendimento-v2
  "/tickets",
  "/clientes",
  "/mensagens",
  "/perfil",        // próprio perfil
];

/** Decide se um papel pode acessar uma rota (match por prefixo). */
export function canAccessPath(role: Role | null | undefined, path: string): boolean {
  if (role !== "agent") return true; // admin, supervisor ou desconhecido (preview)
  return AGENT_PREFIXES.some((p) => path === p || path.startsWith(p + "/"));
}
