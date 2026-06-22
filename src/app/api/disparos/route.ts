import { NextResponse } from "next/server";
import { PAINEL_RP } from "@/lib/painel-rp";

export const dynamic = "force-dynamic";

/**
 * Disparos (proxy POST para o N8N). Aceita os mesmos payloads do painel-rp:
 *  - { action: 'listar' | 'contatos' | 'cancelar', id? }
 *  - criar: { arquivo_url, arquivo_tipo, arquivo_nome, legenda, agendado_para,
 *            enviar_agora, created_by, teste_numeros }
 */
export async function POST(req: Request) {
  try {
    const body = await req.text();
    const res = await fetch(PAINEL_RP.disparos, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    const text = await res.text();
    return new NextResponse(text || "[]", {
      status: res.status,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
