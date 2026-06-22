"use client";

import { useCallback, useEffect, useState } from "react";
import { MessageCircle, ChevronRight, RefreshCw, Trophy, Clock, Zap, Hourglass, CheckCircle2 } from "lucide-react";
import { Card, StatCard } from "@/components/ui";
import { toast } from "@/components/toast";

type Status = "novo" | "em_andamento" | "aguardando_cliente" | "resolvido";

interface Ticket {
  id: string;
  nome_cliente: string;
  telefone: string;
  resumo: string;
  status: Status;
  created_at: string;
  updated_at?: string;
  first_response_at?: string | null;
  resolved_by?: string | null;
  resolved_at?: string | null;
}

interface Metrics {
  media_min?: number; min_min?: number; max_min?: number;
  total_hoje?: number; resolvidos_hoje?: number;
  ultimos_7_dias?: { dia: string; total: number; resolvidos: number }[];
  ranking?: { nome: string; total: number }[];
}

const COLUMNS: { key: Status; label: string; icon: string; accent: string }[] = [
  { key: "novo", label: "Novo", icon: "📭", accent: "border-t-danger" },
  { key: "em_andamento", label: "Em andamento", icon: "⚡", accent: "border-t-warning" },
  { key: "aguardando_cliente", label: "Aguardando cliente", icon: "💤", accent: "border-t-brand" },
  { key: "resolvido", label: "Resolvido", icon: "🎉", accent: "border-t-success" },
];

const NEXT: Record<Status, Status> = {
  novo: "em_andamento",
  em_andamento: "aguardando_cliente",
  aguardando_cliente: "resolvido",
  resolvido: "resolvido",
};

const fmtMin = (min: number) => {
  const m = Math.round(min);
  if (m < 60) return `${m}min`;
  return `${Math.floor(m / 60)}h ${m % 60}min`;
};
const horasEsperando = (t: Ticket) => (Date.now() - new Date(t.created_at).getTime()) / 3_600_000;
const fmtDate = (iso?: string | null) => {
  if (!iso) return "—";
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${p(d.getDate())}/${p(d.getMonth() + 1)} ${p(d.getHours())}:${p(d.getMinutes())}`;
};

export function TicketsClient() {
  const [cards, setCards] = useState<Ticket[]>([]);
  const [metrics, setMetrics] = useState<Metrics>({});
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<{ id: string; status: Status; field: "atender" | "resolver" } | null>(null);
  const [who, setWho] = useState("");

  const load = useCallback(async (silent?: boolean) => {
    if (!silent) setLoading(true);
    try {
      const [pRes, mRes] = await Promise.all([
        fetch("/api/painel", { cache: "no-store" }),
        fetch("/api/metricas", { cache: "no-store" }).catch(() => null),
      ]);
      const pData = await pRes.json();
      const list: Ticket[] = Array.isArray(pData) ? pData : pData?.id ? [pData] : [];
      setCards(list);
      if (mRes?.ok) setMetrics(await mRes.json());
    } catch {
      if (!silent) toast("Erro ao carregar atendimentos", "error");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
    const t = setInterval(() => load(true), 20_000);
    return () => clearInterval(t);
  }, [load]);

  async function patch(id: string, status: Status, resolved_by = "") {
    try {
      const res = await fetch("/api/painel", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id, status, resolved_by }),
      });
      if (!res.ok) throw new Error();
      setCards((cs) => cs.map((c) => (c.id === id ? { ...c, status, resolved_by: resolved_by || c.resolved_by } : c)));
      toast("Atendimento atualizado", "success");
    } catch {
      toast("Erro ao atualizar", "error");
    }
  }

  function advance(t: Ticket) {
    const next = NEXT[t.status];
    if (t.status === "novo") return setModal({ id: t.id, status: "em_andamento", field: "atender" });
    if (next === "resolvido") return setModal({ id: t.id, status: "resolvido", field: "resolver" });
    patch(t.id, next);
  }

  async function confirmModal() {
    if (!modal) return;
    if (!who.trim()) return toast(modal.field === "resolver" ? "Informe quem resolveu" : "Informe quem vai atender", "error");
    await patch(modal.id, modal.status, who.trim());
    setModal(null); setWho("");
  }

  const taxa = (metrics.total_hoje ?? 0) > 0
    ? Math.round(((metrics.resolvidos_hoje ?? 0) / (metrics.total_hoje ?? 1)) * 100) : 0;
  const dias = metrics.ultimos_7_dias ?? [];
  const maxDia = Math.max(1, ...dias.map((d) => Number(d.total) || 0));

  return (
    <div className="space-y-5">
      {/* Métricas */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Tempo médio de resposta" value={metrics.media_min ? fmtMin(metrics.media_min) : "--"} icon={<Clock size={18} />} />
        <StatCard label="Mais rápido" value={metrics.min_min ? fmtMin(metrics.min_min) : "--"} icon={<Zap size={18} />} accent="bg-success-bg text-success" />
        <StatCard label="Mais lento" value={metrics.max_min ? fmtMin(metrics.max_min) : "--"} icon={<Hourglass size={18} />} accent="bg-amber-100 text-warning" />
        <StatCard label="Taxa de resolução (hoje)" value={`${taxa}%`} icon={<CheckCircle2 size={18} />} />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        {/* Gráfico 7 dias */}
        <Card className="lg:col-span-2">
          <p className="mb-3 text-sm font-semibold text-ink">Últimos 7 dias</p>
          {dias.length === 0 ? (
            <p className="py-8 text-center text-xs text-ink-soft">Sem dados ainda</p>
          ) : (
            <div className="flex items-end gap-3" style={{ height: 170 }}>
              {dias.map((d) => (
                <div key={d.dia} className="flex flex-1 flex-col items-center justify-end gap-1">
                  <div className="flex items-end gap-1" style={{ height: 150 }}>
                    <div className="w-3 rounded-t bg-brand/40" style={{ height: Math.max(4, (Number(d.total) / maxDia) * 150) }} title={`${d.total} atendimentos`} />
                    <div className="w-3 rounded-t bg-success" style={{ height: Math.max(4, (Number(d.resolvidos) / maxDia) * 150) }} title={`${d.resolvidos} resolvidos`} />
                  </div>
                  <span className="text-[10px] text-ink-soft">{d.dia}</span>
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* Ranking */}
        <Card>
          <p className="mb-3 flex items-center gap-1.5 text-sm font-semibold text-ink"><Trophy size={14} className="text-warning" /> Ranking de resoluções</p>
          {(metrics.ranking ?? []).length === 0 ? (
            <p className="py-8 text-center text-xs text-ink-soft">Nenhum resolvido ainda</p>
          ) : (
            <div className="space-y-1.5">
              {(metrics.ranking ?? []).map((r, i) => (
                <div key={r.nome + i} className="flex items-center gap-2 rounded-lg bg-canvas px-3 py-1.5 text-xs">
                  <span className={`flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold ${i === 0 ? "bg-warning text-white" : "bg-border text-ink-soft"}`}>{i + 1}</span>
                  <span className="flex-1 truncate text-ink">{r.nome}</span>
                  <span className="font-semibold text-ink-soft">{r.total}</span>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Board */}
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-ink">Fila de atendimentos</p>
        <button onClick={() => load()} className="flex items-center gap-1.5 rounded-lg border border-border px-2.5 py-1.5 text-xs text-ink-soft hover:bg-canvas">
          <RefreshCw size={13} className={loading ? "animate-spin" : ""} /> Atualizar
        </button>
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        {COLUMNS.map((col) => {
          const colCards = cards.filter((c) => c.status === col.key);
          return (
            <div key={col.key} className={`rounded-card border-t-2 bg-canvas/50 ${col.accent}`}>
              <div className="flex items-center justify-between px-3 py-2 text-xs font-semibold text-ink">
                <span>{col.icon} {col.label}</span>
                <span className="rounded-full bg-surface px-2 py-0.5 text-ink-soft">{colCards.length}</span>
              </div>
              <div className="space-y-2 px-2 pb-2">
                {colCards.length === 0 ? (
                  <p className="py-6 text-center text-[11px] text-ink-soft">—</p>
                ) : (
                  colCards.map((t) => {
                    const horas = horasEsperando(t);
                    const urg = t.status === "resolvido" ? "" : horas > 2 ? "ring-1 ring-danger/40" : horas > 0.5 ? "ring-1 ring-warning/40" : "";
                    const tel = (t.telefone || "").replace(/\D/g, "");
                    return (
                      <div key={t.id} className={`rounded-lg bg-surface p-2.5 shadow-card ${urg}`}>
                        <div className="flex items-center gap-1 text-sm font-semibold text-ink">
                          {t.status === "novo" && <span className="text-danger">●</span>}
                          <span className="truncate">{t.nome_cliente}</span>
                        </div>
                        <div className="mt-0.5 text-[11px] text-ink-soft">📱 {t.telefone}</div>
                        <p className="mt-1 line-clamp-3 text-xs text-ink">{t.resumo}</p>
                        {t.status === "resolvido" && t.resolved_by && (
                          <p className="mt-1 text-[10px] text-ink-soft">Resolvido por <strong>{t.resolved_by}</strong> — {fmtDate(t.resolved_at)}</p>
                        )}
                        <div className="mt-2 flex items-center justify-between border-t border-border pt-1.5">
                          <span className="text-[10px] text-ink-soft">⏱️ {t.status === "resolvido" ? fmtDate(t.created_at) : fmtMin(horas * 60)}</span>
                          <div className="flex items-center gap-1">
                            <a href={`https://wa.me/${tel}`} target="_blank" rel="noreferrer" className="rounded p-1 text-success hover:bg-success-bg" title="Abrir WhatsApp"><MessageCircle size={14} /></a>
                            {t.status !== "resolvido" && (
                              <button onClick={() => advance(t)} className="rounded p-1 text-brand hover:bg-brand-light" title="Avançar etapa"><ChevronRight size={14} /></button>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* Modal atender/resolver */}
      {modal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => { setModal(null); setWho(""); }}>
          <div className="w-full max-w-sm rounded-card bg-surface p-5 shadow-pop" onClick={(e) => e.stopPropagation()}>
            <h2 className="mb-3 text-base font-semibold text-ink">{modal.field === "resolver" ? "Resolver atendimento" : "Atender"}</h2>
            <label className="mb-1 block text-xs font-medium text-ink-soft">{modal.field === "resolver" ? "Quem resolveu?" : "Quem vai atender?"}</label>
            <input autoFocus value={who} onChange={(e) => setWho(e.target.value)} onKeyDown={(e) => e.key === "Enter" && confirmModal()}
              className="w-full rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand" placeholder="Nome do atendente" />
            <div className="mt-4 flex justify-end gap-2">
              <button onClick={() => { setModal(null); setWho(""); }} className="rounded-lg px-3 py-2 text-sm text-ink-soft hover:bg-canvas">Cancelar</button>
              <button onClick={confirmModal} className="rounded-lg bg-brand px-3 py-2 text-sm font-medium text-white hover:bg-brand-dark">Confirmar</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
