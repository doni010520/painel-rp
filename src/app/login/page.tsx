"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Eye, EyeOff } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui";

// Login por USUÁRIO: o Supabase Auth usa e-mail por baixo, então completamos o
// domínio interno. Quem digitar um e-mail completo (com "@") é respeitado.
const LOGIN_DOMAIN = "@royalprint.com.br";
function toEmail(login: string): string {
  const v = login.trim();
  return v.includes("@") ? v : `${v}${LOGIN_DOMAIN}`;
}

export default function LoginPage() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [showPw, setShowPw] = useState(false);
  // Estado do desafio 2FA (quando a conta tem TOTP verificado).
  const [mfa, setMfa] = useState<{ factorId: string } | null>(null);
  const [code, setCode] = useState("");

  async function proceedOrChallenge() {
    const supabase = createClient();
    // Verifica se a conta exige 2FA (AAL2) e ainda não cumpriu.
    try {
      const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal && aal.nextLevel === "aal2" && aal.nextLevel !== aal.currentLevel) {
        const { data: f } = await supabase.auth.mfa.listFactors();
        const totp = f?.totp?.find((x) => x.status === "verified");
        if (totp) { setMfa({ factorId: totp.id }); setPending(false); return; }
      }
    } catch { /* sem MFA configurado → segue */ }
    router.push("/dashboard");
  }

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(null);
    if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
      setError("Supabase não configurado (.env.local). Login real indisponível no modo preview.");
      return;
    }
    setPending(true);
    const form = new FormData(e.currentTarget);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email: toEmail(String(form.get("username"))),
      password: String(form.get("password")),
    });
    if (error) {
      setPending(false);
      // Credenciais erradas → mensagem amigável; outros erros (config, rede,
      // Auth quebrado) → mostra a causa real para facilitar o diagnóstico.
      const msg = error.message || "";
      setError(
        /invalid login credentials/i.test(msg)
          ? "Usuário ou senha inválidos."
          : `Falha no login: ${msg}`,
      );
      return;
    }
    await proceedOrChallenge();
  }

  async function verifyMfa(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!mfa || code.trim().length < 6) return;
    setError(null);
    setPending(true);
    const supabase = createClient();
    try {
      const ch = await supabase.auth.mfa.challenge({ factorId: mfa.factorId });
      if (ch.error) throw ch.error;
      const v = await supabase.auth.mfa.verify({ factorId: mfa.factorId, challengeId: ch.data.id, code: code.trim() });
      if (v.error) throw v.error;
      router.push("/dashboard");
    } catch {
      setPending(false);
      setError("Código inválido. Tente novamente.");
    }
  }

  if (mfa) {
    return (
      <AuthShell title="Verificação em duas etapas" subtitle="Digite o código do seu app autenticador">
        <form onSubmit={verifyMfa} className="space-y-4">
          <input
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
            inputMode="numeric"
            autoFocus
            placeholder="000000"
            className="w-full rounded-lg border border-border px-3 py-2 text-center font-mono text-lg tracking-[0.3em] outline-none focus:border-brand"
          />
          {error && <p className="text-xs text-danger">{error}</p>}
          <Button type="submit" className="w-full" disabled={pending || code.length < 6}>
            {pending ? "Verificando..." : "Confirmar"}
          </Button>
        </form>
      </AuthShell>
    );
  }

  return (
    <AuthShell title="Entrar" subtitle="Acesse o seu painel de atendimento">
      <form onSubmit={onSubmit} className="space-y-4">
        <AuthField name="username" type="text" label="Usuário" placeholder="seu.usuario" />
        <div>
          <label className="mb-1 block text-xs font-medium text-ink-soft">Senha</label>
          <div className="relative">
            <input
              name="password"
              type={showPw ? "text" : "password"}
              required
              placeholder="••••••••"
              className="w-full rounded-lg border border-border px-3 py-2 pr-10 text-sm outline-none focus:border-brand"
            />
            <button
              type="button"
              onClick={() => setShowPw((v) => !v)}
              title={showPw ? "Ocultar senha" : "Mostrar senha"}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-ink-soft hover:text-ink"
            >
              {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
            </button>
          </div>
        </div>
        {error && <p className="text-xs text-danger">{error}</p>}
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Entrando..." : "Entrar"}
        </Button>
      </form>
      <p className="mt-4 text-center text-sm text-ink-soft">
        Não tem conta?{" "}
        <Link href="/cadastro" className="font-medium text-brand hover:underline">
          Cadastre-se
        </Link>
      </p>
    </AuthShell>
  );
}

export function AuthShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas p-4">
      <div className="w-full max-w-sm rounded-card bg-surface p-8 shadow-lg">
        <div className="mb-6 flex flex-col items-center text-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo-royalprint.png" alt="Royal Print" className="mb-4 h-24 w-auto rounded-xl" />
          <h1 className="text-xl font-semibold text-ink">{title}</h1>
          <p className="text-sm text-ink-soft">{subtitle}</p>
        </div>
        {children}
      </div>
    </div>
  );
}

export function AuthField({
  name,
  type,
  label,
  placeholder,
}: {
  name: string;
  type: string;
  label: string;
  placeholder?: string;
}) {
  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-ink-soft">{label}</label>
      <input
        name={name}
        type={type}
        required
        placeholder={placeholder}
        className="w-full rounded-lg border border-border px-3 py-2 text-sm outline-none focus:border-brand"
      />
    </div>
  );
}
