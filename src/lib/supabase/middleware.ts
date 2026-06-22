import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { canAccessPath } from "@/lib/access";

const PUBLIC_PATHS = ["/login", "/cadastro", "/auth", "/api/webhooks", "/privacidade"];

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  // Sem env configurado ainda: não bloqueia o app (modo dev/preview).
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL) return response;

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isPublic = PUBLIC_PATHS.some((p) => path.startsWith(p));

  if (!user && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  // RBAC: rota restrita (não liberada ao atendente) → confirma o papel e, se for
  // 'agent', redireciona para o atendimento. Só consulta o banco quando a rota
  // exige (canAccessPath('agent', ...) === false), evitando query em toda request.
  if (user && !isPublic && !canAccessPath("agent", path)) {
    const { data: prof } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    if (prof?.role === "agent") {
      const url = request.nextUrl.clone();
      url.pathname = "/atendimento";
      return NextResponse.redirect(url);
    }
  }

  return response;
}
