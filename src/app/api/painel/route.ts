import { NextResponse } from "next/server";
import { PAINEL_RP } from "@/lib/painel-rp";

export const dynamic = "force-dynamic";

/** Lista os tickets de atendimento (proxy para o N8N painel-rp). */
export async function GET() {
  try {
    const res = await fetch(PAINEL_RP.painel, { cache: "no-store" });
    const text = await res.text();
    return new NextResponse(text || "[]", {
      status: res.status,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}

/** Atualiza um ticket (status / resolved_by) — proxy PATCH para o N8N. */
export async function PATCH(req: Request) {
  try {
    const body = await req.text();
    const res = await fetch(PAINEL_RP.painel, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body,
    });
    const text = await res.text();
    return new NextResponse(text || "{}", {
      status: res.status,
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
