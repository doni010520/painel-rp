import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { PAINEL_RP } from "@/lib/painel-rp";

export const dynamic = "force-dynamic";

/**
 * Upload da mídia de disparo para o Supabase Storage (bucket `disparos`),
 * feito NO SERVIDOR com a service role — diferente do painel-rp antigo, que
 * expunha a service_role no JS do navegador. Devolve a URL pública.
 */
export async function POST(req: Request) {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return NextResponse.json({ error: "Service key não configurada" }, { status: 500 });
  }
  try {
    const form = await req.formData();
    const file = form.get("file");
    if (!(file instanceof File)) {
      return NextResponse.json({ error: "Arquivo ausente" }, { status: 400 });
    }
    const safeName = `${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, "_")}`;
    const buffer = Buffer.from(await file.arrayBuffer());

    const db = createServiceClient();
    const { error } = await db.storage
      .from(PAINEL_RP.bucket)
      .upload(safeName, buffer, { contentType: file.type, upsert: true });
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 502 });
    }
    const { data } = db.storage.from(PAINEL_RP.bucket).getPublicUrl(safeName);
    return NextResponse.json({ url: data.publicUrl, name: file.name, type: file.type });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 });
  }
}
