import { createBrowserClient } from "@supabase/ssr";

// Config pública (URL + anon key) lida em RUNTIME. O layout injeta window.__SB_*
// a partir das env vars do servidor (EasyPanel), então NÃO é preciso "cozinhar" a
// anon key no build — basta configurá-la como env var no deploy. Fallback para o
// valor de build-time (process.env) garante o dev local com .env.local.
function publicEnv(): { url: string; anon: string } {
  if (typeof window !== "undefined") {
    const w = window as unknown as { __SB_URL__?: string; __SB_ANON__?: string };
    return {
      url: w.__SB_URL__ || process.env.NEXT_PUBLIC_SUPABASE_URL || "",
      anon: w.__SB_ANON__ || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "",
    };
  }
  return {
    url: process.env.NEXT_PUBLIC_SUPABASE_URL || "",
    anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "",
  };
}

export function createClient() {
  const { url, anon } = publicEnv();
  return createBrowserClient(url, anon);
}
