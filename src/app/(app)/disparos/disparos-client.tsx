"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Upload, X, Plus, Send, CalendarClock, RefreshCw } from "lucide-react";
import { Card } from "@/components/ui";
import { toast } from "@/components/toast";

interface Disparo {
  id: string;
  created_at: string;
  arquivo_nome?: string;
  arquivo_tipo?: string;
  legenda?: string;
  status: string;
  enviados?: number;
  total?: number;
}

const fileType = (f: File) =>
  f.type.startsWith("image/") ? "image" : f.type.startsWith("video/") ? "video" : "document";
const fmtSize = (b: number) => (b < 1024 * 1024 ? `${Math.round(b / 1024)} KB` : `${(b / 1048576).toFixed(1)} MB`);
const fmtDate = (iso: string) => new Date(iso).toLocaleString("pt-BR");

export function DisparosClient() {
  const [file, setFile] = useState<File | null>(null);
  const [legenda, setLegenda] = useState("");
  const [mode, setMode] = useState<"todos" | "teste">("todos");
  const [testeNums, setTesteNums] = useState<string[]>([]);
  const [numInput, setNumInput] = useState("");
  const [agendar, setAgendar] = useState(false);
  const [data, setData] = useState("");
  const [hora, setHora] = useState("");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const [hist, setHist] = useState<Disparo[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);

  const loadHist = useCallback(async () => {
    try {
      const res = await fetch("/api/disparos", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "listar" }),
      });
      const text = await res.text();
      const parsed = text.trim() ? JSON.parse(text) : [];
      setHist(Array.isArray(parsed) ? parsed : parsed.data ?? []);
    } catch { /* silencioso */ }
  }, []);

  useEffect(() => { loadHist(); }, [loadHist]);

  function addNum() {
    const n = numInput.replace(/\D/g, "");
    if (n.length < 10) return toast("Número inválido (com DDD)", "error");
    if (!testeNums.includes(n)) setTesteNums((a) => [...a, n]);
    setNumInput("");
  }

  async function enviar(enviarAgora: boolean) {
    if (!file) return toast("Selecione um arquivo", "error");
    if (mode === "teste" && testeNums.length === 0) return toast("Adicione ao menos um número de teste", "error");
    let agendadoPara: string | null = null;
    if (!enviarAgora) {
      if (!data || !hora) return toast("Informe data e hora do agendamento", "error");
      agendadoPara = new Date(`${data}T${hora}:00`).toISOString();
    }
    setBusy(true);
    try {
      // 1) Upload server-side da mídia
      setProgress("Enviando arquivo...");
      const fd = new FormData();
      fd.append("file", file);
      const up = await fetch("/api/disparos/upload", { method: "POST", body: fd });
      const upData = await up.json();
      if (!up.ok || !upData.url) throw new Error(upData.error || "Falha no upload");

      // 2) Cria o disparo no N8N
      setProgress("Criando disparo...");
      const res = await fetch("/api/disparos", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          arquivo_url: upData.url,
          arquivo_tipo: fileType(file),
          arquivo_nome: file.name,
          legenda,
          agendado_para: agendadoPara,
          enviar_agora: enviarAgora,
          created_by: "admin",
          teste_numeros: mode === "teste" ? testeNums : null,
        }),
      });
      const result = await res.json().catch(() => ({}));
      if (!res.ok || result.error) throw new Error(result.error || "Erro ao criar disparo");

      toast(enviarAgora ? "Disparo iniciado!" : "Disparo agendado!", "success");
      setFile(null); setLegenda(""); setAgendar(false); setData(""); setHora("");
      loadHist();
    } catch (e) {
      toast((e as Error).message, "error");
    } finally {
      setBusy(false); setProgress("");
    }
  }

  async function cancelar(id: string) {
    if (!confirm("Cancelar este disparo agendado?")) return;
    try {
      await fetch("/api/disparos", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "cancelar", id }),
      });
      toast("Disparo cancelado", "success");
      loadHist();
    } catch { toast("Erro ao cancelar", "error"); }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {/* Novo disparo */}
      <Card>
        <p className="mb-3 text-sm font-semibold text-ink">Novo disparo</p>

        {/* Upload */}
        <input ref={fileRef} type="file" accept="image/*,.pdf,.doc,.docx,.xlsx,video/mp4" hidden
          onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        {!file ? (
          <button onClick={() => fileRef.current?.click()}
            className="flex w-full flex-col items-center gap-2 rounded-lg border-2 border-dashed border-border py-8 text-ink-soft hover:border-brand hover:text-brand">
            <Upload size={22} />
            <span className="text-xs">Clique para escolher a mídia (imagem, vídeo, PDF…)</span>
          </button>
        ) : (
          <div className="flex items-center justify-between rounded-lg border border-border px-3 py-2">
            <div className="min-w-0">
              <p className="truncate text-sm text-ink">{file.name}</p>
              <p className="text-[11px] text-ink-soft">{fmtSize(file.size)} · {fileType(file)}</p>
            </div>
            <button onClick={() => setFile(null)} className="text-ink-soft hover:text-danger"><X size={16} /></button>
          </div>
        )}

        {/* Legenda */}
        <label className="mb-1 mt-3 block text-xs font-medium text-ink-soft">Legenda</label>
        <textarea value={legenda} onChange={(e) => setLegenda(e.target.value)} rows={3}
          className="w-full resize-none rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand"
          placeholder="Texto que acompanha a mídia…" />

        {/* Destino */}
        <label className="mb-1 mt-3 block text-xs font-medium text-ink-soft">Destino</label>
        <div className="flex gap-2">
          {(["todos", "teste"] as const).map((m) => (
            <button key={m} onClick={() => setMode(m)}
              className={`flex-1 rounded-lg border px-3 py-2 text-xs font-medium ${mode === m ? "border-brand bg-brand-light text-brand" : "border-border text-ink-soft"}`}>
              {m === "todos" ? "Todos os contatos" : "Números de teste"}
            </button>
          ))}
        </div>
        {mode === "teste" && (
          <div className="mt-2">
            <div className="flex gap-2">
              <input value={numInput} onChange={(e) => setNumInput(e.target.value)} onKeyDown={(e) => e.key === "Enter" && addNum()}
                placeholder="5581999998888" className="flex-1 rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand" />
              <button onClick={addNum} className="rounded-lg border border-border px-3 text-ink-soft hover:bg-canvas"><Plus size={16} /></button>
            </div>
            {testeNums.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {testeNums.map((n) => (
                  <span key={n} className="flex items-center gap-1 rounded-full bg-canvas px-2 py-0.5 text-[11px] text-ink">
                    {n}<button onClick={() => setTesteNums((a) => a.filter((x) => x !== n))} className="text-ink-soft hover:text-danger"><X size={11} /></button>
                  </span>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Agendamento */}
        <label className="mt-3 flex items-center gap-2 text-xs text-ink">
          <input type="checkbox" checked={agendar} onChange={(e) => setAgendar(e.target.checked)} className="h-4 w-4 accent-brand" />
          Agendar para depois
        </label>
        {agendar && (
          <div className="mt-2 grid grid-cols-2 gap-2">
            <input type="date" value={data} onChange={(e) => setData(e.target.value)} className="rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand" />
            <input type="time" value={hora} onChange={(e) => setHora(e.target.value)} className="rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand" />
          </div>
        )}

        {progress && <p className="mt-3 text-xs text-brand">{progress}</p>}
        <div className="mt-4 flex gap-2">
          {!agendar ? (
            <button disabled={busy} onClick={() => enviar(true)}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-brand py-2.5 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-50">
              <Send size={15} /> Enviar agora
            </button>
          ) : (
            <button disabled={busy} onClick={() => enviar(false)}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-brand py-2.5 text-sm font-medium text-white hover:bg-brand-dark disabled:opacity-50">
              <CalendarClock size={15} /> Agendar disparo
            </button>
          )}
        </div>
      </Card>

      {/* Histórico */}
      <Card>
        <div className="mb-3 flex items-center justify-between">
          <p className="text-sm font-semibold text-ink">Histórico de disparos</p>
          <button onClick={loadHist} className="rounded-lg border border-border p-1.5 text-ink-soft hover:bg-canvas"><RefreshCw size={13} /></button>
        </div>
        {hist.length === 0 ? (
          <p className="py-8 text-center text-xs text-ink-soft">Nenhum disparo ainda</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="text-ink-soft">
                <tr className="border-b border-border">
                  <th className="py-2 pr-2 font-medium">Data</th>
                  <th className="py-2 pr-2 font-medium">Arquivo</th>
                  <th className="py-2 pr-2 font-medium">Status</th>
                  <th className="py-2 pr-2 font-medium">Envio</th>
                  <th className="py-2 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {hist.map((d) => (
                  <tr key={d.id} className="border-b border-border/60">
                    <td className="py-2 pr-2 text-ink-soft">{fmtDate(d.created_at)}</td>
                    <td className="py-2 pr-2 text-ink">{d.arquivo_nome || d.arquivo_tipo}</td>
                    <td className="py-2 pr-2"><span className="rounded-full bg-canvas px-2 py-0.5 text-[10px] text-ink-soft">{d.status}</span></td>
                    <td className="py-2 pr-2 tnum text-ink-soft">{(d.enviados ?? 0)} / {(d.total ?? 0)}</td>
                    <td className="py-2">
                      {d.status === "agendado" && (
                        <button onClick={() => cancelar(d.id)} className="text-[11px] text-danger hover:underline">Cancelar</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </div>
  );
}
