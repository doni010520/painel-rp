import { Scroll } from "@/components/scroll";
import { PageHeader } from "@/components/ui";
import { IntegrationsClient } from "@/components/integrations-client";
import { createClient } from "@/lib/supabase/server";
import { PREVIEW_MODE } from "@/lib/mock";
import type { Integration } from "@/lib/types";

async function getIntegrations(): Promise<Integration[]> {
  if (PREVIEW_MODE) return [];
  const sb = await createClient();
  const { data } = await sb.from("integrations").select("*").order("created_at");
  return (data as Integration[]) ?? [];
}

export default async function IntegracoesPage() {
  const integrations = await getIntegrations();
  return (
    <Scroll>
      <PageHeader title="Integrações" subtitle="Conecte sistemas externos (ERPs, automações) à Royal Print." />
      <IntegrationsClient integrations={integrations} />
    </Scroll>
  );
}
