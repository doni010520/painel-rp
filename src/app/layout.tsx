import type { Metadata, Viewport } from "next";
import "./globals.css";

// Fonte da interface: stack do sistema (definida em globals.css via --font-sans).
// Sem next/font/google para que o build não dependa de rede (Google Fonts) — essencial
// para builds em VPS/EasyPanel sem acesso garantido à internet de build.

export const metadata: Metadata = {
  title: "Royal Print — Atendimento WhatsApp",
  description: "Atendimento e automação de WhatsApp da Royal Print.",
  manifest: "/manifest.json",
  appleWebApp: { capable: true, statusBarStyle: "default", title: "Royal Print" },
};

// Renderiza por requisição (sem prerender estático) para que as env vars públicas
// (URL/anon do Supabase) sejam lidas em RUNTIME — permite configurá-las no EasyPanel
// sem reembutir no build.
export const dynamic = "force-dynamic";

export const viewport: Viewport = {
  themeColor: "#1568dc",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // Config pública lida em RUNTIME e injetada no window — permite definir a anon key
  // como env var no EasyPanel (sem precisar embuti-la no build). Valores públicos.
  const sbUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const sbAnon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  const runtimeConfig = `window.__SB_URL__=${JSON.stringify(sbUrl)};window.__SB_ANON__=${JSON.stringify(sbAnon)};`;
  return (
    <html lang="pt-BR" className="h-full antialiased">
      <body className="min-h-full">
        <script dangerouslySetInnerHTML={{ __html: runtimeConfig }} />
        {children}
      </body>
    </html>
  );
}
