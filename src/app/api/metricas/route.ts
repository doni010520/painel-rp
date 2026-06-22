import { NextResponse } from "next/server";
import { PAINEL_RP } from "@/lib/painel-rp";

export const dynamic = "force-dynamic";

/** Métricas de atendimento (proxy para o N8N painel-rp-metricas). */
export async function GET() {
  try {
    const res = await fetch(PAINEL_RP.metricas, { cache: "no-store" });
    const text = await res.text();
    return new NextResponse(text || "{}", {
      status: res.status,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
